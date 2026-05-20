require 'date'
user = User.find_by_username('root')
if user.nil?
  puts 'no root user'
  exit 1
end
require 'securerandom'
token = PersonalAccessToken.new(user: user, name: 'argocd-temp', scopes: ['api','read_repository','write_repository'])
token.set_token(SecureRandom.hex)
token.expires_at = (Date.today + 365).to_s
if token.save
  puts token.token
else
  puts token.errors.full_messages
end
