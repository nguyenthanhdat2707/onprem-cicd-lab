Secure Software Supply Chain & Runtime Security for Kubernetes
1. Tổng quan
Dự án thiết kế và xây dựng một môi trường DevSecOps/Kubernetes để kiểm chứng bảo mật xuyên suốt vòng đời phần mềm: từ mã nguồn, CI/CD, container artifact, GitOps cho đến workload đang chạy.

Trong chuỗi này, Git repository, CI runner, registry, GitOps controller và Kubernetes cluster có những identity, credential, quyền truy cập và trust boundary khác nhau. Nếu một thành phần bị xâm nhập hoặc cấp quyền quá mức, tác động có thể lan sang những thành phần khác.

Thay vì đánh giá từng công cụ bảo mật riêng lẻ, dự án tập trung kiểm chứng các security control có thực sự ngăn chặn, phát hiện hoặc giới hạn một attack path hay không thông qua các kịch bản kiểm thử lặp lại được.
2. Mục tiêu
- Xây dựng chuỗi kiểm soát bảo mật từ source code → CI/CD → container artifact → deployment → Kubernetes runtime.
- Quét mã nguồn, secret và lỗ hổng; tạo SBOM; ký và xác minh artifact trước khi triển khai.
- Áp dụng admission policy để từ chối workload hoặc artifact vi phạm yêu cầu bảo mật.
- Giới hạn đặc quyền bằng RBAC, ServiceAccount isolation, security context và cơ chế quản lý secret.
- Phân đoạn mạng với NetworkPolicy, hỗ trợ giới hạn lateral movement.
- Thu thập log, metric và security event để phát hiện hoạt động bất thường ở runtime.
- Đánh giá hiệu quả bằng cùng một kịch bản trước và sau hardening, dựa trên attack success, blast radius, detection latency và containment.
3. Phạm vi
Trong phạm vi
- GitLab CI/CD và self-hosted runner.
- Container registry, security scanning, SBOM, image signing/attestation.
- GitOps với Argo CD.
- Kubernetes, admission control, RBAC, ServiceAccount, Pod Security và NetworkPolicy.
- Secret management, runtime detection và security observability.
- Sample application, script/test harness, thu thập evidence và so sánh kết quả kiểm thử.
Ngoài phạm vi cốt lõi
- Tấn công hệ thống production hoặc tài nguyên không thuộc quyền kiểm soát.
- Triển khai bảo mật trên hạ tầng cloud/hybrid quy mô lớn. Phần VM/hybrid có thể mở rộng thêm nhưng không phải yêu cầu bắt buộc.
Nguyên tắc thực nghiệm: chỉ sử dụng lab cô lập, ứng dụng và dữ liệu thử nghiệm.
4. Kiến trúc logic
Developer / Git Repository
           |
           v
      GitLab CI/CD
           |
           +--> Secret / Source / Vulnerability Scan
           +--> Build Container Image
           +--> Generate SBOM
           +--> Sign Image / Attestation
           |
           v
     Container Registry
           |
           v
       GitOps / Argo CD
           |
           v
 Kubernetes Admission Control
   (Verify Artifact + Policies)
           |
           v
    Kubernetes Workloads
      |         |         |
     RBAC   NetworkPolicy  Secret Management
      |         |         |
      +---------+---------+
                |
                v
 Runtime Detection / Observability
                |
                v
 Evidence Store / Scenario Results
                |
                v
 Before-vs-After Security Evaluation
Sơ đồ mô tả luồng logic mục tiêu, không khẳng định mọi thành phần đã được triển khai hoặc rằng tất cả công cụ đều chạy tuần tự trong một pipeline.
5. Công nghệ dự kiến
Nhóm	Công nghệ
Source & CI/CD	GitLab CI/CD, self-hosted runner
Container & Registry	Docker, container registry
Security scanning	Trivy, secret/source scanning
SBOM	Syft
Artifact signing / attestation	Cosign / Sigstore
GitOps	Argo CD
Container orchestration	Kubernetes
Admission & policy	Kyverno, Pod Security
Identity & access	RBAC, ServiceAccount
Network security	NetworkPolicy / Cilium
Secret management	External Secrets Operator
Runtime detection	Falco hoặc Tetragon
Monitoring & logging	Prometheus, Grafana, Loki hoặc OpenSearch
Scenario automation	Script/test harness và kho kết quả kiểm thử


Có thể điều chỉnh hoặc thay thế công cụ nếu vẫn bảo đảm mục tiêu và tiêu chí đánh giá.
6. Security controls
6.1. Software supply chain
- Phát hiện secret và vấn đề bảo mật trong source/pipeline.
- Quét lỗ hổng của image và tạo SBOM.
- Ký image, tạo attestation và kiểm tra tính hợp lệ của artifact.
- Ưu tiên tham chiếu image theo digest để giảm rủi ro thay đổi nội dung dưới cùng một tag.
- Áp dụng policy tại admission để từ chối artifact không đáp ứng điều kiện triển khai.
6.2. Kubernetes security
- RBAC theo nguyên tắc least privilege.
- Cô lập quyền truy cập của ServiceAccount và hạn chế token không cần thiết.
- Giới hạn privileged mode, privilege escalation và Linux capabilities.
- Sử dụng Pod Security và admission policy.
- Áp dụng default-deny và chỉ mở những luồng mạng cần thiết.
- Quản lý secret và giới hạn quyền truy cập vào secret.
6.3. Runtime security & observability
- Theo dõi hoạt động process, shell và network bất thường ở runtime.
- Thu thập security event, Kubernetes audit log, network event và các metric liên quan.
- Liên kết bằng chứng thành incident timeline và attack-path diagram.
- Đánh giá detection, prevention và containment theo từng kịch bản.
7. Kịch bản kiểm thử bảo mật
ID	Kịch bản	Nội dung kiểm thử	Control đánh giá
S01	Lộ secret trong source/CI	Secret thử nghiệm xuất hiện trong source hoặc pipeline context.	Secret scanning, scoped credential, secret management
S02	Artifact bị thay đổi hoặc không được ký	Thử đưa image thiếu chữ ký/attestation hợp lệ vào quy trình triển khai.	Image signing, digest pinning, admission verification
S03	Privileged workload	Thử triển khai workload dùng privileged mode, privilege escalation hoặc capability nguy hiểm.	Kyverno, Pod Security, SecurityContext
S04	ServiceAccount abuse	Kiểm thử quyền Kubernetes API có thể sử dụng từ pod đã bị compromise trong lab.	RBAC least privilege, ServiceAccount isolation
S05	Lateral movement	Thử kết nối từ workload tới service/database nằm ngoài communication path cho phép.	Default-deny, NetworkPolicy
S06	Runtime compromise	Mô phỏng shell/process hoặc network activity bất thường trong container.	Falco/Tetragon, runtime telemetry, audit
S07	CI runner/credential compromise	Kiểm tra phạm vi truy cập của CI job/runner khi credential hoặc quyền được cấp quá rộng.	Runner isolation, credential scoping, permission separation


8. Phương pháp thực nghiệm
1. Threat modeling: xác định asset, trust boundary, threat, attack path và security requirement.
2. Baseline: thiết lập môi trường có chủ đích chưa harden ở một số điểm; chạy kịch bản và lưu evidence.
3. Harden: triển khai security control dựa trên nguyên nhân gốc và attack path được quan sát.
4. Retest: chạy lại đúng kịch bản trong điều kiện tương đương, ghi nhận kết quả.
5. Analyze: đối chiếu pipeline event, Kubernetes audit log, runtime/network event và metric để giải thích kết quả.
Luồng thực nghiệm chính: Attack → Observe → Harden → Retest → Compare.
9. Tiêu chí đánh giá
Chỉ số	Ý nghĩa
Attack success	Kịch bản đạt hay không đạt mục tiêu tấn công đã xác định.
Blast radius	Những tài nguyên, quyền hoặc dịch vụ nằm trong phạm vi ảnh hưởng thực tế.
Privilege gained	Quyền mà tác nhân thử nghiệm có thể đạt được.
Prevention	Control có chặn được hành vi trước khi đạt mục tiêu hay không.
Detection	Hành vi có được phát hiện và ghi nhận đúng hay không.
Detection latency	Khoảng thời gian từ sự kiện tấn công đến khi xuất hiện tín hiệu phát hiện.
Containment	Khả năng giới hạn hoặc cô lập phạm vi ảnh hưởng.
Legitimate workload impact	Ảnh hưởng ngoài ý muốn của hardening đối với workload hợp lệ.


Mỗi kịch bản cần có bằng chứng, kết quả baseline và hardening, nhận định về control hiệu quả và các giới hạn đo lường.
10. Kết quả đầu ra dự kiến
- Lab DevSecOps/Kubernetes có thể tái tạo, gồm CI/CD, registry, GitOps, cluster, sample workload và observability.
- Pipeline bảo mật và tập policy-as-code phục vụ kiểm tra artifact, admission, identity, network và runtime.
- Source code, pipeline configuration, Kubernetes manifests/Helm/Kustomize, Kyverno policies, NetworkPolicies, detection rules và script/test harness.
- Kho lưu scenario run, security event, evidence và dữ liệu so sánh trước/sau.
- Attack-path diagram và incident timeline cho từng kịch bản.
- Bảng kết quả định lượng trước/sau hardening, chỉ ra control nào ngăn chặn, phát hiện hoặc giới hạn phạm vi ảnh hưởng.
- Tài liệu kiến trúc, hướng dẫn tái tạo lab, phương pháp kiểm thử và giới hạn của hệ thống.
11. Cấu trúc tài liệu dự án
- docs/fundamentals/: Software Supply Chain Security, DevSecOps, Kubernetes Security và các mô hình tấn công.
- docs/architecture/: yêu cầu, threat model, trust boundary và kiến trúc.
- docs/supply-chain/: CI/CD, scanning, SBOM, signing/attestation và GitOps.
- docs/kubernetes-security/: admission, RBAC, ServiceAccount, network và secret management.
- docs/runtime-security/: detection, audit, log, metric và evidence collection.
- docs/scenarios/: thiết kế, cách chạy và kết quả từng kịch bản trong lab.
- docs/evaluation/: so sánh baseline/hardening, phân tích kết quả và giới hạn.
Tiêu chí hoàn thành: môi trường tái tạo được, các kịch bản kiểm thử chạy lặp lại được và có evidence đủ để giải thích hiệu quả thực tế của từng security control.