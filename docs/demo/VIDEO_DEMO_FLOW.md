# Flow quay video bảo vệ: supply chain → Kubernetes runtime

Trạng thái: **storyboard dự kiến**, chưa thể quay các cảnh S01/S02/S05/S06
cho đến khi các stage trong [spec dự án](../specs/PROJECT_SPEC.md)
qua gate. Thời lượng mục tiêu: **12–15 phút**. Quay tại nhà, có thể cắt thời gian
chờ CI/Pod nhưng giữ nguyên input, run ID và kết quả gốc; không ghép kết quả từ
hai lần chạy thành một phép thử.

## 1. Câu chuyện muốn người xem nhớ

> Một thay đổi hợp lệ đi qua source, CI, artifact, GitOps và admission để chạy
> trên Kubernetes. Bốn hành vi không mong muốn lần lượt bị chặn tại CI,
> admission, network, hoặc được phát hiện ở runtime. Mỗi kết luận có baseline,
> retest và evidence cùng input.

Phân biệt bằng màu trong slide/overlay: **xanh** = đường hợp lệ,
**đỏ** = thử nghiệm, **vàng** = detection/giới hạn. Gắn `S01/S02/S05/S06`,
`baseline/hardened` và run ID trên mỗi cảnh. Cảnh lỗi phải cho thấy **lý do
đúng**, không chỉ exit code khác 0.

## 2. Shot list theo phút

| Thời gian | Hình cần quay | Lời dẫn/câu hỏi | Bằng chứng phải hiện |
| --- | --- | --- | --- |
| 00:00–00:45 | Slide tên đề tài và sơ đồ `source → CI → registry → Argo CD → admission → workload` | “Tôi kiểm tra control chặn, phát hiện và giới hạn một attack path ra sao.” | Mục tiêu và bốn kịch bản, không liệt kê công cụ dài |
| 00:45–01:30 | Màn hình topology bốn VM, `kubectl get nodes` và health app | “Lab gồm GitLab, runner và Kubernetes hai node; đây là trạng thái trước thí nghiệm.” | Node `Ready`, namespace demo, ngày/giờ quay; không hiện credential |
| 01:30–02:45 | Commit hợp lệ trong GitLab, pipeline stages, image digest/SBOM/signature, GitOps commit, Argo CD `Healthy`, HTTP 200 | “Đây là đường hợp lệ mà hardening phải giữ hoạt động.” | Cùng commit SHA và digest nối từ CI đến manifest; app response |
| 02:45–04:30 | **S01:** hai pipeline cùng input secret giả, baseline rồi hardened | “Nếu source chứa secret giả, gate CI có dừng việc publish không?” | Commit/test file đã che giá trị, scan finding ID, pipeline status, registry không có image mới ở retest |
| 04:30–06:30 | **S02:** hai lần apply unsigned digest vào namespace thử; sau policy, thêm signed digest hợp lệ | “Registry có image chưa đủ; admission phải kiểm ai đã ký chính digest đó.” | Baseline pod được nhận; retest bị từ chối kèm lý do; signed digest chạy/HTTP 200 |
| 06:30–08:45 | **S05:** từ cùng frontend pod gọi API và decoy trước/sau policy | “Default-deny chặn đường ngang nhưng giữ đường ứng dụng cần.” | Bốn kết quả probe: API pass/decoy pass → API pass/decoy fail; policy revision; DNS pass |
| 08:45–10:45 | **S06:** chạy lệnh shell thử nghiệm, trước/sau bật rule; màn hình event | “Runtime sensor phát hiện hoạt động, không tự chặn shell.” | Trigger timestamp, alert timestamp, pod UID, rule ID; một benign probe không alert |
| 10:45–12:15 | Bảng kết quả trước/sau và một attack-path diagram | “Control nào chặn, control nào chỉ phát hiện?” | Bốn hàng S01/S02/S05/S06, run IDs, latency S06, legitimate impact |
| 12:15–13:15 | Slide giới hạn + đường dẫn repo/evidence | “Kết quả chỉ có hiệu lực trong lab và tập probe này.” | Giới hạn mẫu đo, phạm vi namespace, các mục S03/S04/S07 chưa đánh giá lõi |

Có thể kéo tới 15 phút nếu CI cần thêm giải thích, nhưng không thêm cảnh chỉ để
trưng giao diện. Nếu giảng viên giới hạn ngắn hơn, giữ đường hợp lệ, S02, S05,
S06 và bảng kết quả; S01 chuyển thành đoạn evidence ngắn. Không tuyên bố S01
được demo trực tiếp nếu nó chỉ còn trong phụ lục.

## 3. Cách quay từng phép thử

Mỗi cảnh dùng cùng khuôn:

1. Hiện **mục tiêu** một dòng, input hash/manifest và run ID.
2. Hiện **baseline**: control chưa enforce trong phạm vi test, chạy probe,
   lưu kết quả và thời gian.
3. Hiện **thay đổi control**: diff policy/CI rule và revision; tránh cảnh cài
   đặt dài không đóng góp cho lập luận.
4. Hiện **retest** cùng input, namespace/target và probe; nêu rõ điều gì đã
   được giữ tương đương, điều gì không thể giữ tương đương.
5. Hiện **kiểm tra đường hợp lệ** để chứng minh control không phá app.
6. Hiện một dòng **kết luận có giới hạn** và đường dẫn evidence theo run ID.

Không chỉ quay UI trạng thái `Failed`: đặt cửa sổ terminal cạnh UI để người
xem thấy input, API response, policy revision và app health. Nếu policy/app
được thay trong lúc quay, ghi rõ đó là bước hardening có chủ đích.

## 4. Chuẩn bị trước khi bấm Record

- Chạy preflight Stage 0: node, DNS, registry, Argo CD, admission, sensor và
  app. Nếu lỗi, sửa và kiểm lại trước khi quay; không giả lập cảnh thành công.
- Đồng bộ giờ VM; đặt terminal hiển thị UTC cho event timestamp và overlay giờ
  địa phương nếu cần. Chọn font lớn, độ phân giải 1080p, ẩn notification.
- Tạo bốn cặp run ID cố định; lưu commit SHA, image digest, GitOps revision và
  policy revision trong một `demo-index.md` (sẽ tạo khi triển khai harness).
- Dùng **secret giả** đã kiểm rule, image unsigned/wrong-key do lab tạo,
  decoy service trong lab và lệnh shell test đã định nghĩa. Không gõ token,
  password, kubeconfig, signing key hoặc dashboard admin credential trên màn
  hình; kiểm cả command history và tên file.
- Dọn tài nguyên test cũ theo runbook, rồi chụp snapshot trạng thái đầu vào.
  Không reset cluster hoặc xóa dữ liệu rộng chỉ để có cảnh baseline.
- Quay một lượt rehearsal, đối chiếu video với evidence. Nếu phép thử không
  cho kết quả dự đoán, giữ nguyên evidence và giải thích hoặc quay sau khi đã
  sửa nguyên nhân; không thay nhãn kết quả.

## 5. Dữ liệu mang theo video

Nộp kèm `demo-index.md` trỏ từ mỗi timestamp video tới
`evidence/<scenario-id>/<run-id>/`. Gói tối thiểu gồm spec, manifest/script
input, CI/policy revision, dữ liệu đo đã lọc secret, bảng so sánh và hướng dẫn
tái tạo. Video là phần kể chuyện; evidence gốc là phần chứng minh. Nếu giảng
viên yêu cầu chỉ nộp video, đặt bảng kết quả và mã run ID ngay trong cảnh cuối
để vẫn kiểm tra được các kết luận chính.
