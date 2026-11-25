# Kiến trúc repository cho đồ án

Quyết định ngày 25/11/2026: dùng **modular monorepo** cho source, CI, Ansible
và tài liệu; dùng **một GitOps repo riêng** cho trạng thái triển khai mà Argo CD
theo dõi. Hai GitLab project đã được tạo; thay đổi source đi qua nhánh feature,
còn GitOps repo chưa có chart/manifest trong workspace này.

```text
DACN2-Final/                       # repo kỹ thuật / source project
├── .gitlab-ci.yml                 # entrypoint GitLab CI tại gốc repo
├── ci/                            # job CI theo ứng dụng
│   ├── demo-app.yml
│   └── runner-smoke.yml           # kiểm tra executor thủ công
├── apps/
│   └── demo-app/                 # app, test, Dockerfile, Compose local
├── ansible/
│   ├── ansible.cfg
│   ├── inventory/                 # host và group vars
│   └── playbooks/                 # automation cho lab
├── docs/                          # spec, kiến trúc, slide, kết quả kiểm tra
├── .agents/                       # hướng dẫn agent hiện có
├── .codex/                        # cấu hình Codex hiện có
└── .claude/                       # chỗ dành cho Claude nếu cần sau này

cicd-gitops-lab/                   # GitLab project riêng cho GitOps
├── charts/demo-app/              # Helm chart của app
├── environments/lab/             # values pin image digest
└── argocd/                        # Application/AppProject theo phạm vi demo
```

`.claude/` là vị trí quy ước, chưa được tạo. Có thể đặt `AGENTS.md` và
`CLAUDE.md` ở gốc khi cần hướng dẫn chung; hướng dẫn chỉ áp dụng cho một app
có thể nằm trong chính thư mục app. Chỉ commit các file hướng dẫn/cấu hình đã
review. Cache, trạng thái máy local, token, kubeconfig và private key không
thuộc source repo; các thư mục agent không chứa logic triển khai.

Source project: `git@10.20.0.10:root/cicd-lab.git`.
GitOps project: `git@10.20.0.10:root/cicd-gitops-lab.git` (nhánh mặc định
`main`). Cấu trúc Helm ở trên là mục tiêu cho Stage 2, chưa có chart/manifest
được tạo trong workspace này.

## Quy tắc đặt file

- `apps/<name>/`: mã nguồn, test, Dockerfile, tài liệu chạy local. Compose ở
  đây chỉ phục vụ phát triển/kiểm tra local.
- `.gitlab-ci.yml`: điểm vào mặc định của GitLab ở gốc repo. Nó `include:local`
  các job từ `ci/`. Job app đổi thư mục vào `apps/<name>/` trước khi test/build.
  Khi có thêm app, thêm file job tương ứng trong `ci/` và giới hạn trigger theo
  path nếu chi phí pipeline bắt đầu đáng kể.
- `ansible/`: toàn bộ cấu hình, inventory, playbook, template và file hỗ trợ
  của Ansible. Chạy các lệnh từ thư mục này để Ansible tự nạp `ansible.cfg`.
  Tên playbook và đường dẫn tương đối bên trong playbook được giữ nguyên.
- GitOps repo: chỉ chứa desired state, Helm chart/values, image tham chiếu
  bằng digest và policy
  triển khai. Argo CD đọc repo này. CI source không giữ kubeconfig hoặc chạy
  `kubectl apply` trực tiếp; promotion qua thay đổi GitOps được review.
- Evidence chứa credential thật không được commit vào bất kỳ repo nào.

## Vì sao chọn cấu trúc này

GitLab mặc định tìm `.gitlab-ci.yml` ở gốc project. Đặt file trong thư mục
app chỉ đúng khi thư mục app tự nó là gốc một project GitLab, điều hiện tại
không đúng với workspace này. Giữ job cụ thể trong `ci/` giúp root pipeline
ngắn, nhưng version job vẫn đi cùng commit của source. Tách GitOps thành
project riêng tạo ranh giới quyền giữa build/publish và deploy.

Đổi lại repo kỹ thuật chứa cả Ansible và app. Hiện chỉ có một app demo và một
lab, nên tách thêm source/infra project sẽ tăng số repo và quy trình đồng bộ
mà chưa tạo lợi ích rõ. Có thể tách infra thành repo riêng khi có nhiều app,
nhóm quyền khác nhau hoặc vòng đời thay đổi độc lập.

Tham chiếu: [GitLab CI/CD settings](https://docs.gitlab.com/administration/settings/continuous_integration/)
và [include:local](https://docs.gitlab.com/ci/yaml/#includelocal).
