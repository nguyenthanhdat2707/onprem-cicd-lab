# Secure Software Supply Chain & Runtime Security for Kubernetes

Repo này chứa automation Ansible cho lab Proxmox/Kubernetes, tài liệu đồ án
DevSecOps và mã nguồn demo app. Cluster hai node đã được ghi nhận nghiệm thu;
pipeline hiện mới có unit test, còn registry, GitOps và security controls đang
ở mức kế hoạch.

Tài liệu bắt đầu tại [mục lục docs](docs/README.md),
[đề cương](docs/project/PROJECT_BRIEF.md), [spec chi tiết](docs/specs/PROJECT_SPEC.md)
và [flow quay video](docs/demo/VIDEO_DEMO_FLOW.md).

Kiến trúc repo nằm tại [repository architecture](docs/architecture/REPOSITORY_ARCHITECTURE.md).
Chuẩn bị Stage 1 trên máy local nằm tại [demo app](apps/demo-app/README.md) và
[kế hoạch Stage 1](docs/architecture/STAGE1_LOCAL_PLAN.md). Trạng thái lab
kiểm tra trực tiếp ngày 25/11 nằm tại
[Stage 0 status](docs/infrastructure/STAGE0_STATUS_2026-11-25.md).
[Phương án HTTPS/registry](docs/infrastructure/GITLAB_TLS_REGISTRY_PLAN.md)
ghi các gate cần xử lý trước khi tạo repo GitLab và publish image.

## Ansible cho các VM Ubuntu trên Proxmox

Toàn bộ cấu hình Ansible nằm trong [ansible/](ansible/).
Các lệnh Ansible bên dưới giả định terminal đang ở thư mục này. Từ gốc repo,
chạy `cd ansible` một lần trước khi dùng các lệnh đó; terminal mới cần chạy
lại bước này.

Inventory hiện có bốn VM: `gitlab-server` (`10.20.0.10`, user `gitlab`),
`gitlab-runner` (`10.20.0.11`, user `runner`), `k8s-worker` (`10.20.0.12`,
user `tdat`) và `k8s-controller` (`10.20.0.15`, user `k8s-controller`).
`bootstrap_ssh.yml` thêm SSH key cho từng VM. `prepare_vms.yml` chỉ áp dụng
cho controller và worker.

## Trước khi chạy

1. Xác nhận các user trong inventory đăng nhập SSH được. User trên controller
   và worker cần quyền `sudo` để chạy `prepare_vms.yml`.
2. Xác nhận host key từ console của từng VM rồi thêm vào `known_hosts`. Ansible giữ
   `host_key_checking=True`; không tự động tin một host key chưa kiểm chứng.
3. Đảm bảo máy chạy Ansible có route `10.20.0.0/24` qua next hop
   `192.168.101.81`. `ansible/playbooks/preflight.yml` kiểm tra route và dừng nếu khác.
   Nó không sửa cấu hình mạng. Route đã được người dùng đặt tạm thời qua `.81`
   và cổng SSH của cả bốn IP đã mở tại lần kiểm tra gần nhất. Khi route mất
   sau khởi động lại, người quản trị máy Ansible có thể đặt lại và kiểm bằng:

   ```bash
   sudo ip route replace 10.20.0.0/24 via 192.168.101.81 dev wlan0
   ip route get 10.20.0.12
   ip route get 10.20.0.15
   ```

   Lệnh `ip route` này không tự tồn tại sau khi khởi động lại; cấu hình route
   cố định phụ thuộc cách máy quản lý mạng.
4. Chuẩn bị public key `~/.ssh/id_ed25519.pub`, hoặc đổi
   `bootstrap_public_key_file` trong `ansible/inventory/group_vars/all.yml`.

SSH key đã được kiểm tra trên cả bốn VM; các lệnh bootstrap dưới đây chỉ cần
khi dựng lại VM hoặc chuyển sang máy điều khiển Ansible khác:

```bash
cd ansible
ansible-playbook playbooks/bootstrap_ssh.yml --limit gitlab-server --ask-pass
ansible-playbook playbooks/bootstrap_ssh.yml --limit gitlab-runner --ask-pass
ansible-playbook playbooks/bootstrap_ssh.yml --limit k8s-worker --ask-pass
ansible-playbook playbooks/bootstrap_ssh.yml --limit k8s-controller --ask-pass
```

## Chuẩn bị controller và worker cho Kubernetes

`prepare_vms.yml` chỉ nhắm vào VM 104 và VM 100. Nó kiểm tra Ubuntu 24.04,
ít nhất 5 GiB trống trên `/` và không có Docker container đang chạy trên
worker. Sau đó nó:

- Cài `kubeadm`, `kubelet`, `cri-tools` trên cả hai node; cài `kubectl` trên
  controller. APT repo chỉ chứa nhánh Kubernetes `1.36`. Lần chạy đầu cài bản
  vá mới nhất có trong repo rồi giữ các phiên bản đã cài bằng dpkg hold.
- Cài `containerd` từ Ubuntu trên controller. Worker giữ `containerd.io` hiện
  có của Docker. Cả hai nhận cấu hình CRI và `systemd` cgroup; chỉ restart
  containerd khi cấu hình đổi. Playbook không thay gói Docker của worker.
- Tắt swap hiện tại và ngăn nó bật lại từ `/etc/fstab`, bật IPv4 forwarding,
  đặt hostname `k8s-worker`/`k8s-controller` và cập nhật `/etc/hosts`.
- Chỉ tạo các thư mục cấu hình hệ thống cần dùng như `/etc/apt/keyrings` và
  `/etc/containerd`. Không tạo thư mục dự án tùy ý trên node.

Chạy từng máy từ `ansible/` để nhập đúng mật khẩu `sudo` của user tương ứng:

```bash
ansible-playbook playbooks/preflight.yml
ansible-playbook playbooks/prepare_vms.yml --limit k8s-controller --ask-become-pass
ansible-playbook playbooks/prepare_vms.yml --limit k8s-worker --ask-become-pass
```

Nếu một bước lỗi, dừng và kiểm tra trạng thái thực tế trước khi thử lại. Các
task sửa file cấu hình có tạo bản sao lưu, nhưng playbook không tự rollback
dịch vụ hoặc package. Worker hiện có Docker đang chạy; thay cấu hình containerd
có thể ảnh hưởng workload Docker dù playbook đã chặn khi còn container đang
chạy. Sau khi xóa project GNS3, dung lượng trống đo được khoảng 12 GiB trên
worker và 7,7 GiB trên controller; chưa chứng minh đủ cho toàn bộ image và
telemetry của đồ án.

`prepare_vms.yml` chỉ chuẩn bị node. Các playbook `cluster_*.yml` đã dựng
cluster bằng kubeadm và Cilium; Argo CD, GitLab và runner thuộc stage sau.
Cluster dùng địa chỉ `10.20.0.15`/`10.20.0.12` trên `ens19`; hai VM còn có
interface DHCP `192.168.101.x` trên `ens18`.

## Bàn giao cluster 23/11/2026

- Controller và worker đều đăng nhập SSH bằng key và trả `pong` qua Ansible.
- `k8s-controller` (`10.20.0.15`) và `k8s-worker` (`10.20.0.12`) đều `Ready`
  với Kubernetes v1.36.6. Cilium DaemonSet, Cilium operator và CoreDNS đều
  đạt `2/2`.
- `cluster_verify.yml` đã kiểm tra tên node, InternalIP và trạng thái các
  thành phần. `cluster_smoke.yml` đã xác nhận DNS và truy cập Service từ pod
  trên worker tới pod trên controller, sau đó xóa namespace thử nghiệm.
- Controller đã có cấu hình Netplan cho `10.20.0.15/24` trên `ens19`, nhưng
  chưa thử khởi động lại để xác nhận IP tự lên. Route từ máy chạy Ansible tới
  `10.20.0.0/24` qua `192.168.101.81` vẫn là cấu hình tạm.
- GitLab, runner, Registry, Argo CD và observability chưa nằm trong stage
  cluster này.

Tên hiển thị VM trong Proxmox là một cấu hình riêng, không đổi khi hostname
Ubuntu đổi. Chưa có playbook đổi tên Proxmox vì chưa xác nhận địa chỉ, phiên
bản và cách đăng nhập host `pve`.

## Dựng cluster hai node

Xem [kế hoạch và điều kiện dừng](docs/infrastructure/K8S_CLUSTER_PLAN.md). Các playbook
`cluster_*.yml` phục vụ cluster mới trên VM 104 và 100. Chạy từ `ansible/`
và kiểm tra kết quả từng bước trước khi sang bước tiếp. Mật khẩu `sudo`
của controller và worker có thể khác nhau; không lưu vào inventory.

Đầu tiên, chạy preflight chỉ đọc trên từng VM và xem output UFW:

```bash
ansible-playbook playbooks/cluster_preflight.yml --limit k8s-controller --ask-become-pass
ansible-playbook playbooks/cluster_preflight.yml --limit k8s-worker --ask-become-pass
```

Người dùng chọn tạm giữ UFW inactive. `cluster_firewall.yml` chỉ gọi
`ufw disable` nếu node đang active; nó không xóa các rules đã lưu.
Sau preflight, thực hiện từng bước:

```bash
ansible-playbook playbooks/cluster_firewall.yml --limit k8s-controller --ask-become-pass
ansible-playbook playbooks/cluster_firewall.yml --limit k8s-worker --ask-become-pass
ansible-playbook playbooks/cluster_init.yml --limit k8s-controller --ask-become-pass
ansible-playbook playbooks/cluster_cilium.yml --limit k8s-controller --ask-become-pass
ansible-playbook playbooks/cluster_join.yml --limit k8s-worker
ansible-playbook playbooks/cluster_verify.yml --limit k8s-controller
ansible-playbook playbooks/cluster_smoke.yml --limit k8s-controller
```

`cluster_join.yml` tự hỏi hai mật khẩu `sudo` qua prompt riêng và không ghi
chúng vào file. Nó dùng token một giờ, không in token ra log và xóa file join
tạm sau khi chạy. `cluster_smoke.yml` tạo namespace tạm để kiểm DNS và Service
qua hai node, rồi xóa namespace nếu mọi probe thành công; nếu probe lỗi thì
giữ lại để chẩn đoán. Không chạy tiếp bước sau khi một playbook báo lỗi.
