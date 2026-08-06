# Crea el proyecto 'mlezcano-gitlab-demo' bajo el usuario root si no existe.
# Se ejecuta dentro del pod de GitLab vía `gitlab-rails runner`
user = User.find_by_username('root')
project = Project.find_by_full_path('root/mlezcano-gitlab-demo')

if project.nil?
  project = Projects::CreateService.new(user, {
    name:             'mlezcano-gitlab-demo',
    path:             'mlezcano-gitlab-demo',
    visibility_level: Gitlab::VisibilityLevel::PRIVATE
  }).execute
end

abort(project.errors.full_messages.join(', ')) \
  if project.respond_to?(:errors) && project.errors.any?
puts project.http_url_to_repo
