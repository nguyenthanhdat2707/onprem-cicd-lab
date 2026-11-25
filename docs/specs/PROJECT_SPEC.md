# Spec dự án: Secure Software Supply Chain & Runtime Security for Kubernetes

Trạng thái: **bản thảo để cùng rà soát**, ngày 23/11/2026. Tài liệu này cụ thể
hóa [đề cương](../project/PROJECT_BRIEF.md) thành phạm vi thực hiện và tiêu chí
nghiệm thu. Nó chưa phải lệnh triển khai lên lab.

## 1. Mục đích và kết quả cuối

Xây một lab có thể tái tạo để chứng minh security control tác động lên một
attack path cụ thể ra sao. Kết quả bảo vệ là video quay trước tại nhà, kèm
source, cấu hình, kịch bản chạy và evidence đủ để người khác kiểm lại kết luận.
Một demo đạt yêu cầu phải cho thấy cùng input và mục tiêu trước/sau hardening,
không chỉ trình diễn giao diện các công cụ.

**Luồng hợp lệ cần chứng minh:** sửa sample app → GitLab CI kiểm tra và build →
image được quét, tạo SBOM, ký → image vào registry → cập nhật digest trong GitOps
repository → Argo CD đồng bộ → admission chấp nhận → app chạy và trả HTTP 200.
CI không giữ kubeconfig và không triển khai trực tiếp bằng `kubectl`.

**Luồng kiểm thử bảo mật:** Attack → Observe → Harden → Retest → Compare. Bốn
kịch bản lõi được chọn là S01, S02, S05, S06. S03 là cảnh bổ sung nếu kịp;
S04 và S07 nằm trong phạm vi nghiên cứu sau khi bốn kịch bản lõi đã có evidence.

## 2. Căn cứ hiện tại và điều chưa biết

- **Confirmed từ repo:** inventory có VM GitLab `10.20.0.10`, runner
  `10.20.0.11`, controller `10.20.0.15`, worker `10.20.0.12`. README và
  [kế hoạch cluster](../infrastructure/K8S_CLUSTER_PLAN.md) ghi nhận hai node Kubernetes
  v1.36.6 `Ready`, Cilium và CoreDNS hoạt động, smoke test DNS/Service đạt ngày
  23/11/2026. Đây là kết quả được ghi trong repo, chưa phải phép đo mới.
- **Confirmed từ repo:** tại lần đo được ghi, controller còn khoảng 7,7 GiB và
  worker còn khoảng 12 GiB trên `/`. Route từ máy Ansible là tạm thời; controller
  chưa được kiểm chứng tự lấy lại IP `10.20.0.15` sau lần reboot tiếp theo.
- **Unknown:** trạng thái thực tế, phiên bản, RAM/disk và TLS của GitLab/runner;
  registry đã bật hay chưa; khả năng DNS và pull image giữa bốn VM; ngân sách
  lưu trữ cho image, log và video. Stage tiếp theo phải đo trước khi cài thêm.
- **Inferred:** nếu đặt Argo CD, Kyverno, Falco và hệ log đầy đủ lên hai node
  ngay, dung lượng còn lại có thể là điểm nghẽn. Spec ưu tiên evidence tối thiểu
  trước và chỉ thêm dashboard sau khi có số đo.

## 3. Phạm vi và lựa chọn thiết kế

### Mục tiêu

1. Bốn kịch bản lõi chạy lại được bằng script hoặc runbook có input cố định.
2. Mỗi kịch bản có baseline, kết quả sau hardening, một kiểm tra workload hợp lệ
   và bằng chứng liên kết bằng run ID.
3. Phân biệt prevention, detection và containment; không gọi một cảnh báo là
   biện pháp ngăn chặn.
4. Tất cả thay đổi đối với cluster dùng manifest/values lưu trong repo, phiên
   bản được ghim khi triển khai và có bước kiểm tra trước/sau.

### Không nằm trong bản demo lõi

- Đánh chiếm thật, dùng credential thật, tấn công ngoài lab, hay tác động lên
  production/shared infrastructure.
- Dựng HA, nhiều cluster hoặc cloud/hybrid.
- Chứng minh tất cả bảy kịch bản ở cùng độ sâu. S03/S04/S07 được giữ như phần
  mở rộng, không được ghi là “đạt” nếu chưa có baseline và retest.
- Bắt buộc chạy đồng thời Prometheus, Grafana, Loki/OpenSearch và External
  Secrets Operator. Các công cụ này chỉ thêm nếu đáp ứng ngân sách tài nguyên
  và đóng góp bằng chứng rõ ràng.

### Các cách tổ chức đã cân nhắc

| Cách | Lợi ích | Đổi lại |
| --- | --- | --- |
| Làm đủ S01–S07 và toàn bộ stack observability trước khi quay | Bao phủ rộng đề cương | Dễ thiếu thời gian/disk; mỗi kịch bản khó đo sâu |
| **Bốn kịch bản đại diện, evidence chuẩn, mở rộng sau** | Có một câu chuyện xuyên source → runtime, đo trước/sau được | S04/S07 chưa có kết luận thực nghiệm lõi |
| Một attack path rất sâu | Dễ giải thích blast radius | Không thể hiện chuỗi supply chain và runtime của tên đề tài |

Chọn cách thứ hai vì mục tiêu chính là kiểm chứng control, không phải số công cụ
được cài. Đây là đề xuất thiết kế của Codex dựa trên đề cương và tài nguyên đã
ghi nhận; người thực hiện có thể điều chỉnh sau khi đo stage 0.

## 4. Ranh giới tin cậy và quyền

| Thành phần | Được làm | Không được cấp mặc định |
| --- | --- | --- |
| Developer/Git repo | Đề xuất source và GitOps change qua review | Signing key, kubeconfig admin |
| GitLab CI/runner | Build, scan, push registry; job trên nhánh được bảo vệ mới ký | Quyền cluster-admin, quyền sửa GitOps tự động |
| Registry | Lưu image và chữ ký/attestation gắn với digest | Quyền truy cập Kubernetes |
| Argo CD | Đọc GitOps repo, đồng bộ namespace/app đã chỉ định | Đồng bộ tùy ý mọi namespace |
| Kyverno admission | Xác thực image của namespace demo bằng public key | Private signing key |
| Sample workload | Gọi đúng service cần dùng, đọc secret thử nghiệm được cấp | API token hoặc secret ngoài phạm vi app |
| Evidence collector | Đọc trạng thái, event và kết quả kịch bản | Sửa policy hoặc workload |

Phân biệt GitLab repo chứa source/pipeline với GitOps repo chứa manifests. Có
thể là hai project trên cùng GitLab instance. Mọi image triển khai được tham
chiếu theo digest. CI tạo SBOM dạng CycloneDX JSON bằng Syft, quét source/image
bằng Trivy, ký digest bằng Cosign key pair lưu private key trong cơ chế secret
được bảo vệ của CI; public key mới được đưa vào policy. Chọn key pair cho lab
vì không phụ thuộc OIDC/Sigstore bên ngoài. Nó đòi hỏi quy trình giữ và xoay
key; keyless là hướng mở rộng sau. Signature được admission kiểm tra; SBOM và
attestation được lưu, xác minh trong pipeline. Việc **bắt buộc xác minh SBOM
attestation ngay tại admission** là một gate mở rộng riêng, không được ngầm
coi là đã đạt khi chỉ kiểm signature.

Policy chỉ áp dụng namespace demo; namespace hệ thống không bị dùng làm baseline.
Kịch bản không làm suy yếu control ở phạm vi toàn cluster. Baseline được tạo
bằng namespace/test branch riêng hoặc policy ở chế độ quan sát, rồi đổi sang
enforce trong cùng phạm vi và chạy lại cùng input. Trước lúc quay, chụp lại
trạng thái cluster và đảm bảo test namespace không còn tài nguyên cũ.

## 5. Spec các stage

Mỗi stage có một gate. Nếu gate fail, dừng và ghi evidence; không tự chuyển sang
stage sau. Các thao tác lên VM/cluster thuộc bước triển khai riêng, không được
ủy quyền bởi việc duyệt tài liệu này.

### Stage 0 — Kiểm tra lab và ổn định nền

**Đầu vào:** cluster được ghi là đã nghiệm thu. **Việc cần thiết kế/chuẩn bị:**
đo CPU, RAM, disk, route, DNS, TLS, pull image, trạng thái dịch vụ GitLab và
runner; reboot có kiểm soát để xác minh IP controller chỉ khi có phương án khôi
phục đã được duyệt. Xác định chỗ lưu evidence/video ngoài filesystem của node.

Lập threat model đầu tiên: asset, identity, trust boundary và attack path cho
S01/S02/S05/S06; gắn mỗi control với một giả thuyết có thể kiểm chứng. **Gate:**
hai node `Ready`, CoreDNS/Cilium healthy, route và hostname ổn định, bốn VM
truy cập được; trạng thái GitLab/runner/registry được xác định rõ, kể cả khi
chưa cài; có số đo dung lượng và ngân sách image, sensor, log retention trước
khi cài. **Evidence:** `preflight.json`, sơ đồ trust boundary, node/pod status,
dung lượng, DNS/TLS probe, danh sách phiên bản. **Điểm dừng:** controller mất
IP, route thay đổi, không có đường đi tin cậy giữa các VM, hoặc không đủ
headroom theo ngân sách đã tính.

### Stage 1 — Sample app, GitLab CI và registry

**Mục tiêu:** cài/cấu hình GitLab và runner trên VM đã dành sẵn nếu Stage 0
cho thấy chúng chưa sẵn sàng; xác nhận registry, DNS và TLS tin cậy trước khi
build. Tạo một app nhỏ, deterministic, có endpoint `/healthz` và một luồng
`frontend → api`; một `decoy` HTTP service chỉ dùng cho S05. Tách namespace
`demo-app` và `demo-decoy`; dùng dữ liệu giả. CI có jobs test → secret/source
scan → build → image vulnerability scan → SBOM → publish. Chốt policy fail của
Trivy theo severity và cơ chế allowlist có lý do/expiry, không bỏ qua lỗi tùy
tiện. Dùng registry GitLab nếu khả dụng; không dựng registry thứ hai khi chưa
cần. Runner là VM riêng, executor và quyền được kiểm tra trước khi chọn cách
build; không mặc định dùng privileged Docker-in-Docker.

**Gate:** GitLab/runner/registry hoạt động qua TLS phù hợp; commit hợp lệ tạo
image có digest, SBOM gắn đúng digest, báo cáo scan
được lưu; app chạy và trả HTTP 200; commit chứa secret giả bị phát hiện bởi
rule đã kiểm thử. **Evidence:** pipeline URL/ID, commit SHA, image digest,
SBOM, scan JSON đã lọc dữ liệu nhạy cảm, response app. **Điểm dừng:** runner
cần privileged không có lý do, registry auth/TLS không rõ, image không pull
được từ node, hoặc báo cáo scan không gắn đúng commit/digest.

### Stage 2 — Ký artifact và GitOps

**Mục tiêu:** CI chỉ ký image digest sau khi các gate của Stage 1 đạt. Lưu chữ
ký và SBOM attestation trong registry; xác minh lại bằng public key. Một thay
đổi GitOps manifest chỉ rõ digest đã kiểm tra; Argo CD đồng bộ app vào namespace
demo. Việc promotion qua review thủ công là đủ cho demo và giữ CI tách khỏi
cluster. Argo CD chỉ có quyền cần cho app/namespace này.

**Gate:** image đã ký được xác minh, image khác digest hoặc chưa ký không xác
minh được; thay đổi GitOps dẫn tới Argo CD `Synced`/`Healthy`, app vẫn trả
HTTP 200. **Evidence:** CI signing/verify log đã lọc, digest, commit GitOps,
Argo CD revision và trạng thái app. **Điểm dừng:** ký tag thay vì digest, private
key lộ trong job log, hoặc Argo CD cần quyền cluster rộng không giải thích được.

### Stage 3 — Admission, Pod Security và identity

**Mục tiêu:** Kyverno xác minh signature của image trong `demo-app` bằng public
key và từ chối unsigned/wrong-key image. Chỉ kích hoạt enforce sau khi đã đo
baseline S02. Namespace demo dùng Pod Security Admission phù hợp; S03 thử
privileged workload nếu thêm vào video. App có ServiceAccount riêng, tắt
automount token nếu không gọi Kubernetes API; role/binding được kiểm tra với
`kubectl auth can-i`. Secret của app là dữ liệu giả, chỉ cấp cho workload cần
nó; External Secrets Operator chỉ thêm khi đã chọn nguồn secret bên ngoài và
đo được giá trị của việc thêm thành phần này. Chọn loại policy Kyverno theo phiên bản thực sự được ghim
và kiểm compatibility với Kubernetes 1.36, tránh sao chép manifest từ tài liệu
version khác.

**Gate:** signed digest được chấp nhận; unsigned/wrong-key digest bị từ chối
với lý do đúng; app hợp lệ vẫn healthy. Nếu kiểm S03: privileged pod bị từ
chối, pod hợp lệ được chấp nhận. **Evidence:** manifest input, API response,
policy revision, admission event, app health. **Điểm dừng:** policy chặn pod
hệ thống, webhook không hoạt động hoặc fail-open ngoài phạm vi đã thiết kế.

### Stage 4 — Phân đoạn mạng

**Mục tiêu:** đo S05 trước policy: pod frontend kết nối được `api` và `decoy`.
Sau đó áp default-deny ingress/egress trong namespace demo rồi allow đúng DNS
và `frontend → api`; namespace decoy vẫn tách riêng. Dùng Kubernetes
NetworkPolicy trên Cilium cho yêu cầu cơ bản, chỉ dùng CiliumNetworkPolicy nếu
cần tính năng riêng. Kiểm tra cả sender egress và receiver ingress để không
nhầm nguyên nhân bị chặn.

**Gate:** cùng probe trước/sau cho thấy truy cập decoy chuyển từ thành công
sang thất bại, trong khi `frontend → api`, DNS và HTTP app hợp lệ vẫn thành
công. **Evidence:** policy revision, pod IP/labels, output probe kèm timestamp,
Cilium flow/drop nếu có. **Điểm dừng:** DNS hoặc app hợp lệ hỏng; không tiếp
tục quay cho tới khi policy được sửa và retest.

### Stage 5 — Runtime detection và evidence

**Mục tiêu:** chạy S06 trong pod thử nghiệm có image được phép: tạo shell/process
test bằng lệnh xác định trước, không dùng payload khai thác thật. Baseline lưu
thời điểm trigger do harness tạo và kiểm tra không có alert từ runtime rule;
đây không phải bằng chứng rằng kernel không có event. Sau đó cài một sensor
đã chọn (ưu tiên Falco nếu kernel/eBPF và tài nguyên phù hợp), bật rule cụ thể
cho shell trong container, xuất event có timestamp và định danh pod. Không mặc
định coi alert là containment. Nếu không thể chạy Falco ổn định, thử Tetragon
trong một spike có giới hạn trước khi đổi lựa chọn của spec.

**Gate:** ba lần retest cùng hành vi tạo ba alert đúng pod trong thời gian đo
được; ít nhất một hành vi app hợp lệ không tạo alert; không rơi syscall event
ở mức làm sai phép đo. **Evidence:** event JSON, pod UID, rule ID, thời điểm
trigger/alert, log phiên bản sensor, số đo tài nguyên. **Điểm dừng:** sensor
làm node NotReady, event thiếu định danh để ghép, hoặc baseline/retest khác
input.

### Stage 6 — So sánh, tái tạo và đóng gói video

**Mục tiêu:** script `run-scenario` nhận ID, mode, run ID; tạo/cấp input, chạy
probe, lưu output có cấu trúc, kiểm cleanup. Thực hiện ít nhất ba run cho mỗi
mode của bốn kịch bản lõi nếu chi phí cho phép; mọi thất bại được ghi, không
chỉ chọn run đẹp. Tạo bảng trước/sau và sơ đồ attack path ngắn. Viết runbook
tái tạo, danh sách version/digest, giới hạn và video storyboard.

**Gate:** mỗi kịch bản có baseline + hardened run, evidence truy xuất được từ
commit/digest/policy revision, workload hợp lệ vẫn pass; video khớp evidence
gốc và không hiển thị secret thật. **Điểm dừng:** một control không tạo ra thay
đổi như dự đoán; ghi là kết quả âm tính và giải thích, không sửa dữ liệu.

## 6. Đặc tả kịch bản lõi

| ID | Input/mục tiêu cố định | Baseline kỳ vọng | Hardened kỳ vọng | Control và phép đo chính |
| --- | --- | --- | --- | --- |
| S01 | Commit chứa **chuỗi giả** khớp rule secret test trên branch demo; thử đưa vào pipeline | Job không có gate phát hiện, pipeline đi tiếp | Trivy secret gate fail, không publish image | Prevention tại CI; pipeline result, commit SHA, finding ID; không in giá trị secret |
| S02 | Cùng manifest tham chiếu unsigned image digest từ registry lab; sau đó signed digest của cùng app | Unsigned pod được admission nhận trong namespace test | Unsigned/wrong-key bị từ chối; signed digest được nhận | Admission decision, pod creation, app health; không dùng image public tùy ý |
| S05 | Từ frontend pod gọi API hợp lệ và decoy service không nằm trong communication path | Cả hai kết nối thành công | API thành công, decoy bị chặn | Reachability, Cilium drop/flow; xác nhận DNS vẫn hoạt động |
| S06 | Chạy cùng lệnh shell test trong container thử nghiệm, ba lần | Hành vi xảy ra; chưa có alert runtime rule | Hành vi tạo alert đúng pod; app hợp lệ không alert | Detection latency, true positive, false positive trong tập probe nhỏ |

S01 không đo “secret đã lộ ra ngoài” vì chỉ có chuỗi giả. S02 chỉ chứng minh
admission kiểm signature của digest theo key được tin cậy, không chứng minh
image không có lỗ hổng. S05 đo reachability từ điểm thử, không chứng minh mọi
đường lateral movement đều bị chặn. S06 đo detection trong lab, không chứng
minh sensor có khả năng containment tự động.

**S03 bổ sung:** một manifest privileged và một manifest hợp lệ trong namespace
demo; Pod Security/Kyverno từ chối input đầu, chấp nhận input sau. **S04/S07
mở rộng:** cần threat model, identity và credential giả tách biệt, quyền trước/
sau đo bằng API probes, rồi mới quyết định có đưa vào video hay không.

## 7. Đo lường và định dạng evidence

Mỗi run lưu trong `evidence/<scenario-id>/<run-id>/`; không đưa secret thật,
kubeconfig, token, private key hoặc raw dump chứa chúng vào repo. Tối thiểu:

```text
metadata.json       scenario, mode, timestamp UTC, commit, image digest,
                    policy revision, tool versions, namespace, pod UID
input/              manifest/script và hash của input
observations.json   probe result, API decision, alert/flow IDs, timestamps
legitimate.json     health/DNS/allowed path sau control
summary.md          expected vs actual, giới hạn, nguyên nhân sai lệch
```

`Attack success` là binary theo mục tiêu của kịch bản; `prevention` chỉ tính
khi control chặn trước mục tiêu; `detection latency = alert timestamp - event
timestamp` với cùng nguồn thời gian/đồng bộ NTP. `Blast radius` chỉ báo cáo
tập tài nguyên thực sự được probe, không suy rộng toàn cluster. Mọi phép đo
ghi rõ `N` và điều kiện run. Có bảng một hàng cho mỗi run và bảng tổng hợp
baseline/hardened; không áp phần trăm thống kê cho mẫu quá nhỏ.

## 8. Điều kiện hoàn thành dự án

1. Stage 0–6 qua gate, hoặc deviation được ghi rõ với lý do và ảnh hưởng.
2. Bốn kịch bản lõi có script/runbook chạy lại và kết quả trước/sau có thể
   truy ngược về input, commit, digest, policy và event.
3. Đường triển khai hợp lệ hoạt động sau hardening; không làm hỏng DNS/API hoặc
   workload ngoài namespace demo.
4. Video ngắn trình bày câu hỏi, pipeline hợp lệ, bốn kịch bản, kết quả đo và
   giới hạn; file evidence và hướng dẫn tái tạo đi kèm.
5. Không có credential thật trong repo, artifact/video hoặc màn hình quay.

Flow từng cảnh nằm trong [storyboard video](../demo/VIDEO_DEMO_FLOW.md).

## 9. Các quyết định cần xác nhận trước khi triển khai

- Rubric môn học có bắt buộc đủ S01–S07, công cụ cụ thể, thời lượng video hoặc
  định dạng nộp khác không? Nếu có, phải sửa phạm vi lõi và storyboard trước
  khi lập implementation plan.
- Bốn VM và cluster có hoàn toàn dành riêng cho đồ án không, và người thực hiện
  có quyền cấu hình GitLab/runner/registry, thêm controller vào cluster và tăng
  disk/RAM khi cần không? Nếu là tài nguyên chia sẻ, cần cách cô lập khác.
- Số đo Stage 0 quyết định có đủ sức chạy Argo CD, Kyverno và runtime sensor
  cùng lúc không; nếu thiếu, tăng disk/RAM qua thay đổi hạ tầng được duyệt hoặc
  ghi rõ cách quay theo từng pha mà không ngụy tạo tính đồng thời.
- Chọn phiên bản GitLab, runner executor, registry TLS, Kyverno policy API và
  Falco driver sau khi kiểm tra compatibility thực tế; ghim version/checksum
  trong implementation plan.
- Chốt nơi lưu video/evidence và thời lượng video theo yêu cầu giảng viên nếu
  có. Bản flow hiện đề xuất khoảng 12–15 phút.

## 10. Tài liệu kỹ thuật dùng để thiết kế

- [GitLab runner security](https://docs.gitlab.com/runner/security/),
  [CI variables](https://docs.gitlab.com/ci/variables/) và
  [registry authentication](https://docs.gitlab.com/user/packages/container_registry/authenticate_with_container_registry/).
- [Trivy filesystem/secret scan](https://trivy.dev/docs/dev/target/filesystem/)
  và [exit code](https://trivy.dev/docs/latest/configuration/others/).
- [Syft SBOM formats](https://github.com/anchore/syft) và
  [Cosign signature verification](https://docs.sigstore.dev/cosign/verifying/verify/).
- [Kyverno image verification](https://kyverno.io/docs/policy-types/image-validating-policy/)
  và [Kubernetes Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/).
- [Argo CD automated sync](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/),
  [Cilium network policy](https://docs.cilium.io/en/stable/security/policy/kubernetes/)
  và [Falco default rules](https://falco.org/docs/reference/rules/default-rules/).
