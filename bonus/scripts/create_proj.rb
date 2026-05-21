ns = Namespace.find_by_path('root')
if ns.nil?
  puts 'Namespace root no encontrado'
  exit 1
end

project = Project.new(name: 'playground-demo', path: 'playground-demo', namespace_id: ns.id, visibility_level: 20)
if project.save
  puts "Proyecto creado en DB: #{project.path}"
else
  puts "No pudo guardarse el proyecto: #{project.errors.full_messages.join(', ')}"
  # continue if already exists
end

begin
  project.create_repository unless project.repository.exists?
rescue => e
  puts "create_repository: #{e.message}"
end

user = User.find_by_username('root')
if user.nil?
  puts 'Usuario root no encontrado'
  exit 1
end

content = <<~YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wil-playground
  namespace: dev
spec:
  replicas: 1
  selector:
    matchLabels:
      app: playground
  template:
    metadata:
      labels:
        app: playground
    spec:
      containers:
      - name: wil-playground
        image: wil42/playground:v1
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8888
---
apiVersion: v1
kind: Service
metadata:
  name: wil-playground
  namespace: dev
spec:
  type: NodePort
  ports:
  - port: 8888
    targetPort: 8888
    nodePort: 30080
  selector:
    app: playground
YAML

begin
  if project.repository.exists? && !project.repository.tree('master').any? { |e| e[:path] == 'deployment.yaml' }
    project.repository.create_file(user, 'deployment.yaml', content, 'initial commit', 'master')
    puts 'deployment.yaml creado en repo'
  else
    puts 'Repo no creado o deployment.yaml ya existe'
  end
rescue => e
  puts "Error creando archivo en repo: #{e.message}"
end

puts project.http_url_to_repo
