# Stage 0 — Kiểm kê tài nguyên lab ngày 23/11/2026

Phạm vi: đọc trực tiếp Proxmox qua `ssh proxmox`, và bốn VM trong
`ansible/inventory/hosts.yml` qua SSH key (đường dẫn hiện tại, sau khi gom
Ansible ngày 25/11). Không thay đổi Proxmox, VM, Kubernetes hay
file cấu hình. Số liệu là ảnh chụp tại thời điểm kiểm tra, không phải peak hoặc
cam kết tài nguyên lâu dài. Đơn vị GiB = 2³⁰ byte.

**Quyết định của chủ dự án ngày 24/11/2026:** tiếp tục triển khai đồ án trên
hạ tầng hiện có. Quyết định này chấp nhận việc theo dõi và xử lý giới hạn tài
nguyên trong từng stage; nó không thay đổi các số đo và rủi ro ghi bên dưới.

## Kết luận nhanh

**Đã có nền tảng để tiếp tục Stage 0 và dựng thử từng thành phần:** Proxmox
truy cập được, GitLab và runner có service đang chạy, hai node Kubernetes
`Ready`, Cilium/CoreDNS đang `Running`.

**Chưa đủ bằng chứng để xác nhận toàn bộ stack DevSecOps chạy đồng thời ổn
định.** Host chỉ còn khoảng **8,9 GiB RAM khả dụng**; pool chứa disk VM còn
**69,0 GiB**; filesystem `/` của controller còn **5,2 GiB**, worker **10,3
GiB**, runner **8,9 GiB**. GitLab guest còn khoảng **1,2 GiB RAM khả dụng**.
Các giới hạn này cần được tính với image, build cache, registry, Argo CD,
Kyverno, runtime sensor và log retention trước khi cài thêm.

## 1. Proxmox host `pve`

| Hạng mục | Số liệu trực tiếp |
| --- | ---: |
| Phiên bản | Proxmox VE 9.1.1, kernel 6.17.2-1-pve |
| CPU | 1 socket, 12 nhân, 24 luồng; Intel Xeon E5-2676 v3 |
| RAM vật lý | 31,2 GiB tổng; 22,3 GiB đang dùng; 8,9 GiB khả dụng |
| Swap | 8 GiB; chưa dùng tại thời điểm đọc |
| Ổ vật lý | 1 NVMe 238,5 GiB |
| Root LV của host | 69,2 GiB theo `lsblk`; root filesystem còn khoảng 54,5 GiB khả dụng theo API |
| `local-lvm` cho disk VM | 140,9 GiB tổng; 71,8 GiB đã dùng; 69,0 GiB khả dụng |
| VM | 5 chạy, 1 tắt; không có LXC được liệt kê |

`local` là storage directory trên root filesystem; không cộng dung lượng
`local` và root như hai nơi trống độc lập. `local-lvm` là thin pool khác trên
cùng ổ NVMe. Dung lượng disk ảo được cấp cho các VM không bằng dung lượng vật
lý đã tiêu thụ trong thin pool.

| VMID | Tên hiển thị Proxmox | Trạng thái | vCPU | RAM cấu hình | Disk ảo danh nghĩa |
| ---: | --- | --- | ---: | ---: | ---: |
| 100 | GNS3 | running | 8 | 20 GiB | 50 GB |
| 101 | VM 101 | stopped | 8 | 20 GiB | 100 GB theo `qm list` |
| 102 | Runner | running | 4 | 8 GiB | 32 GB |
| 103 | Gitlab-Server | running | 8 | 8 GiB | 79 GB |
| 104 | Observability | running | 4 | 5,9 GiB | 32 GB |
| 105 | Routing-Subnet | running | 1 | 2 GiB | 32 GB |

Năm VM đang chạy được cấu hình tổng **25 vCPU và khoảng 43,9 GiB RAM**, lớn
hơn 24 luồng/31,2 GiB RAM vật lý. Đây là **overcommit cấu hình**, không chứng
minh đang thiếu RAM ngay lúc đo. `pvesh` báo RAM hiện dùng của từng VM thấp hơn
RAM cấu hình ở một số VM; mức sử dụng đồng thời khi build/scan vẫn chưa đo.
VM 105 cũng dùng tài nguyên host dù không thuộc bốn VM chính của đồ án.

## 2. Bốn VM chính — số liệu bên trong guest

`MemAvailable` lấy từ `free -b`; dung lượng `/` lấy từ `df -B1 /`. RAM khả dụng
của các guest **không được cộng** để suy ra RAM vật lý còn trống trên Proxmox.

| VMID / vai trò theo guest | Hostname hiện tại | vCPU | RAM guest tổng / khả dụng | Disk ảo | Filesystem `/` tổng / còn trống | Swap |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 100 / Kubernetes worker | `k8s-worker` | 8 | 19,5 / 18,5 GiB | 50 GB | 23,5 / **10,3 GiB** | 0 |
| 102 / GitLab runner | `homelab-runner` | 4 | 7,8 / 7,1 GiB | 32 GB | 14,7 / **8,9 GiB** | 0 |
| 103 / GitLab server | `homelab-gitlabserver` | 8 | 7,8 / **1,2 GiB** | 79 GB | 37,6 / 24,0 GiB | 4 GiB, gần như chưa dùng |
| 104 / Kubernetes controller | `k8s-controller` | 4 | 5,7 / 4,4 GiB | 32 GB | 14,7 / **5,2 GiB** | 0 |

Tên hiển thị VM 100/104 trên Proxmox khác hostname trong guest. VMID và
hostname guest xác nhận hai VM đó là worker/controller đang dùng. Root logical
volume trong các VM nhỏ hơn disk ảo; ví dụ controller có disk 32 GB nhưng root
filesystem chỉ khoảng 14,7 GiB. **Chưa xác nhận** phần còn lại có thật sự là
VG free có thể cấp cho root hay không: lệnh `vgs` dưới user thường bị từ chối
quyền đọc lock LVM. Không lên kế hoạch mở rộng filesystem chỉ dựa trên
`lsblk`.

## 3. Dịch vụ và cluster

- **Confirmed:** `gitlab-runsvdir` trên VM 103 và `gitlab-runner` trên VM 102
  đều `active/running`. Điều này chưa xác nhận GitLab UI/API, registry hay
  runner registration/job hoạt động end-to-end.
- **Confirmed:** `kubelet` và `containerd` trên VM 100/104 đều `active/running`.
  `kubectl get nodes -o wide` trả cả hai node `Ready`, Kubernetes v1.36.6,
  InternalIP `10.20.0.12`/`10.20.0.15`.
- **Confirmed:** `kubectl get pods -A -o wide` chỉ thấy các pod hệ thống;
  Cilium, Cilium operator và CoreDNS đều `Running` tại thời điểm đọc.
- **Cần điều tra:** pod `etcd` và `kube-apiserver` trên controller có 11 lần
  restart, lần gần nhất khoảng 3,5 giờ trước lúc kiểm tra. Dữ liệu hiện tại
  không xác định nguyên nhân. Đây là rủi ro ổn định trước khi thêm admission
  webhook và GitOps controller.

## 4. Đánh giá khả năng đáp ứng dự án

| Hạng mục | Đánh giá hiện tại | Bằng chứng / giới hạn |
| --- | --- | --- |
| Nền Kubernetes hai node | **Đạt ở thời điểm đọc** | Hai node `Ready`, pod hệ thống `Running`; cần giải thích restart control plane |
| GitLab + runner cơ bản | **Chưa đủ kiểm chứng end-to-end** | Service active; chưa thử UI/API, registry, runner nhận job |
| RAM host cho toàn stack | **Rủi ro** | 8,9 GiB khả dụng; RAM cấu hình VM đã overcommit; chưa đo peak build/scan |
| Dung lượng VM/pool | **Rủi ro cao nhất trước khi cài thêm** | Controller `/` 5,2 GiB, worker 10,3 GiB, runner 8,9 GiB; thin pool 69,0 GiB còn trống |
| Observability đầy đủ | **Chưa thể cam kết** | Chưa có ngân sách RAM/disk và retention cho log/metric/security event |

**Cách thực hiện theo quyết định trên:** đo tài nguyên và kiểm tra ổn định
control plane trước/sau mỗi thành phần mới; nếu gặp thiếu disk/RAM hoặc lỗi
cluster, dừng stage đó để chẩn đoán. Không mặc định rằng số liệu guest còn trống
là RAM vật lý còn trống trên Proxmox.

## 5. Việc cần kiểm tiếp theo

1. Đọc VG/LV free trong từng guest bằng quyền đọc phù hợp và xác minh nơi lưu
   `/var/lib/containerd`, GitLab data, runner cache; không sửa partition/LV ở
   bước kiểm tra.
2. Xem lịch sử restart/event của `etcd` và `kube-apiserver`, kiểm tra IP tĩnh
   controller sau reboot và route từ máy điều khiển.
3. Kiểm tra GitLab UI/API, registry TLS, runner registration và một job nhỏ;
   service `active` không đủ làm bằng chứng pipeline sẵn sàng.
4. Định ngân sách cho image, build cache, SBOM/signature, số ngày giữ log và
   số lần chạy kịch bản; đo host RAM và thin pool sau mỗi thành phần mới.

## 6. Nguồn đo và giới hạn truy cập

Nguồn Proxmox: `pveversion`, `pvesh get /nodes/pve/status`, `pvesh get
/nodes/pve/qemu`, `pvesm status`, `qm list`, `lsblk`. Nguồn guest: `hostnamectl
--static`, `nproc`, `free -b`, `df -B1 /`, `lsblk`, `systemctl show`; nguồn
cluster: `kubectl get nodes -o wide`, `kubectl get pods -A -o wide`.

Không chạy benchmark hoặc tải thử, không đo IOPS/network throughput, không
đọc cấu hình chứa secret. VM 105 không được đăng nhập. Lệnh `vgs` không chạy
được dưới tài khoản guest thường nên VG free vẫn là **Unknown**.
