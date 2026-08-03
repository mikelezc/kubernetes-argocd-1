# Crea (recreándolo si ya existía) un Personal Access Token de lectura/escritura
# para que Argo CD pueda autenticarse contra el repositorio. Se ejecuta dentro
# del pod toolbox de GitLab vía `gitlab-rails runner`
# (scripts/create-gitlab-project-and-push.sh).
user = User.find_by_username('root')
user.personal_access_tokens.where(name: 'mlezcano-argo').delete_all

response = PersonalAccessTokens::CreateService.new(
  current_user:    user,
  target_user:     user,
  organization_id: user.organization_id,
  params: { name: 'mlezcano-argo', scopes: [:read_repository, :write_repository] }
).execute

abort(response.message) unless response.success?
puts response.payload[:personal_access_token].token
