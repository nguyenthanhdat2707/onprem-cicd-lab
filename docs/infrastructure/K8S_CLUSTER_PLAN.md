# Kế hoạch dựng cluster Kubernetes trên Proxmox

Trạng thái: **đã triển khai và nghiệm thu ngày 23/11/2026**. Phạm vi đợt này
là cluster Kubernetes hai node; GitLab, runner, Registry, Argo CD và
observability được thực hiện sau.

## Bằng chứng trước triển khai (22/11/2026)

| Vai trò | VM | Địa chỉ node | Tài nguyên hiện thấy | Trạng thái |
| --- | --- | --- | --- | --- |
| Control plane | 104 `k8s-controller` | `10.20.0.15` trên `ens19` | 4 vCPU, 5.7 GiB RAM, 7.7 GiB trống trên `/` | Ubuntu 24.04.4; kubeadm/kubelet 1.36.6; containerd active |
| Worker | 100 `k8s-worker` | `10.20.0.12` trên `ens19` | 8 vCPU, 19 GiB RAM, 12 GiB trống trên `/` | Ubuntu 24.04.4; kubeadm/kubelet 1.36.6; containerd và Docker active |

Trước khi triển khai, hai node đi trực tiếp với nhau qua `ens19`. Cả hai không có
`/etc/kubernetes/admin.conf`, không có CNI config và API port 6443 chưa mở;
đây là cluster mới. Swap đã tắt, IPv4 forwarding là `1`, đồng bộ NTP báo `yes`.
Ansible ping được cả hai qua SSH key. Người chạy Ansible có route
`10.20.0.0/24` qua `192.168.101.81`; route này hiện chưa được cấu hình cố định.
`sudo ufw status` trên controller trả `inactive` dù dịch vụ systemd đang
active. Người dùng chọn giữ UFW tắt trong đợt bootstrap này; trạng thái
worker sẽ được đọc trong preflight. Rules hiện có không bị xóa.

## Kết quả nghiệm thu (23/11/2026)

- API server đã phản hồi `/readyz`; `k8s-controller` và `k8s-worker` đều
  `Ready`, với InternalIP lần lượt là `10.20.0.15` và `10.20.0.12`.
- Cilium DaemonSet `2/2`, Cilium operator `2/2` và CoreDNS `2/2`.
- `cluster_verify.yml` chạy thành công. `cluster_smoke.yml` xác nhận DNS và
  HTTP qua Service giữa hai pod trên hai node; namespace thử nghiệm đã xóa.
- Sau khi VM khởi động lại mà mất địa chỉ `10.20.0.15`, etcd không thể bind
  vào IP này và API server tạm dừng. Controller đã có file Netplan đặt IP
  tĩnh cho `ens19`; cluster phục hồi sau khi IP xuất hiện. Khả năng tự lên IP
  ở lần khởi động tiếp theo **chưa được kiểm chứng**.
- Route `10.20.0.0/24` qua `192.168.101.81` trên máy chạy Ansible vẫn chưa
  được lưu cố định. UFW đang inactive theo quyết định tạm thời của stage này.

## Cấu hình được duyệt trước triển khai

- Kubernetes giữ phiên bản đã cài `v1.36.6`, runtime `containerd` qua
  `unix:///run/containerd/containerd.sock`.
- API server quảng bá `10.20.0.15:6443`. Node InternalIP buộc là
  `10.20.0.15` và `10.20.0.12` qua `nodeRegistration.kubeletExtraArgs`
  trong cấu hình kubeadm `v1beta4`; tránh kubelet chọn IP DHCP trên `ens18`.
- Pod CIDR `10.244.0.0/16`; Service CIDR `10.96.0.0/12`. Cần xác nhận
  không trùng route đang dùng trước khi khởi tạo.
- Cilium `1.20.5` làm CNI, IPAM lấy PodCIDR từ Kubernetes, dùng chế độ
  tunnel/VXLAN trên mạng node `10.20.0.0/24`. Giữ kube-proxy mặc định để
  giảm số thay đổi trong lần dựng đầu. Helm client thuộc nhánh `3.21.x`,
  phù hợp Kubernetes 1.36; ghim phiên bản và checksum khi viết automation.
- Control plane vẫn giữ taint mặc định; workload thường sẽ chạy trên worker.

## Thứ tự thực hiện và điểm dừng

1. **Preflight chỉ đọc:** kiểm tra identity hai VM, route hai chiều, CIDR,
   trạng thái swap, CRI, phiên bản, dung lượng, trạng thái chưa có cluster,
   và `sudo ufw status numbered` trên từng VM. Chạy `kubeadm config validate`
   trên file cấu hình sinh từ template. Nếu phát hiện dấu vết cluster,
   route trùng hoặc firewall không rõ, dừng trước khi sửa.
2. **Giữ UFW inactive:** đọc trạng thái trên từng node, chạy `ufw disable`
   chỉ nếu đang active, rồi kiểm lại `inactive` và SSH. Đây là quyết định
   tạm cho lab: khi API server lên, cần kiểm tra phạm vi truy cập thực tế
   trên cả `10.20.0.x` và `192.168.101.x`. Bật lại UFW với rules giới hạn
   là một thay đổi riêng sau khi cluster hoạt động.
3. **Tạo control plane:** Ansible ghi cấu hình kubeadm không chứa secret,
   dùng `kubeadm init --config` trên VM 104. Giữ `admin.conf` trên controller;
   cấp kubeconfig cho user `k8s-controller` trên chính VM với quyền `0600`.
   Kiểm tra API, chứng chỉ và node IP trước bước kế.
4. **Cài Cilium:** cài Helm client được kiểm checksum trên controller rồi
   `helm install` Cilium chart phiên bản ghim với values lưu trong repo.
   Chờ agent trên controller; operator và CoreDNS được nghiệm thu đầy đủ sau
   khi worker join. Nếu fail, dừng để đọc events/logs; không reset cluster.
5. **Join worker:** tạo bootstrap token ngắn hạn trên controller, giữ token
   trong Ansible `no_log` và file cấu hình tạm `0600` trên worker; dùng
   `kubeadm join --config`. Xóa file chứa token sau join. Kiểm tra InternalIP
   là `10.20.0.12` và worker `Ready`.
6. **Nghiệm thu:** hai node `Ready`, InternalIP đúng dải `10.20.0.x`,
   Cilium trên hai node và CoreDNS `Running`, `kubectl get pods -A` không có
   lỗi bất thường. Chạy probe DNS và kết nối pod qua hai node trong namespace
   tạm, lưu kết quả đã lọc secret, rồi xóa đúng các đối tượng probe đó.

## Cách chạy và giới hạn quyền

Automation tách playbook theo bước để người vận hành thấy kết quả từng
điểm dừng. Các user SSH hiện không có `sudo` không cần mật khẩu; Ansible cần
`--ask-become-pass` khi áp dụng. Không lưu sudo password, bootstrap token,
private key hoặc kubeconfig vào repo hay log. Người dùng chạy các lệnh từ
terminal và gửi output đã lọc secret nếu agent không thể nhập sudo password
an toàn vào phiên SSH.

Thay đổi áp dụng trực tiếp lên hai VM và đối tượng Kubernetes mới. Không tác
động GitLab/runner/Registry/Argo CD. Một control plane duy nhất không có HA;
worker phụ thuộc VM 104 để quản trị và tạo workload mới.

## Phục hồi và bằng chứng

- Trước khi đổi, lưu output preflight, phiên bản và cấu hình containerd/
  kubeadm dự kiến. Sau mỗi bước, lưu trạng thái node/pod và event liên quan.
- Nếu `kubeadm init`, Helm hoặc join báo lỗi hay trạng thái khác dự kiến,
  dừng; kiểm tra hiện trạng rồi trình cách sửa tiếp. Không tự retry thao tác
  thay đổi trạng thái.
- `kubeadm reset` và xóa dữ liệu etcd là thao tác phá hủy; chỉ dùng sau khi
  đánh giá hiện trạng và được duyệt riêng. Helm rollback chỉ áp dụng được
  khi đã có release revision tốt trước đó. Snapshot Proxmox trước triển khai
  là lựa chọn phục hồi mạnh hơn nếu người quản trị có quyền tạo snapshot.

## Tài liệu kỹ thuật

- [Kubernetes v1.36: tạo cluster bằng kubeadm](https://v1-36.docs.kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)
- [Kubernetes v1.36: kubeadm config v1beta4](https://v1-36.docs.kubernetes.io/docs/reference/config-api/kubeadm-config.v1beta4/)
- [Cilium 1.20.5: cài với kubeadm](https://docs.cilium.io/en/stable/installation/k8s-install-kubeadm/)
- [Cilium: Kubernetes compatibility](https://docs.cilium.io/en/stable/network/kubernetes/compatibility/)
- [Helm: version support](https://v3.helm.sh/docs/v3/topics/version_skew/)
- [Kubernetes: ports and protocols](https://kubernetes.io/docs/reference/networking/ports-and-protocols/)
- [Cilium: VXLAN firewall requirement](https://docs.cilium.io/en/stable/network/concepts/routing/)
