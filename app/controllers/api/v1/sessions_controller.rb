class Api::V1::SessionsController < Api::ApiController
  skip_before_action :auth0_authenticate_request!

  def create
    command = AuthenticateUser.call(params[:email], params[:password])

    if command.success?
      render json: { auth_token: command.result }
    else
      render json: { error: command.errors }, status: :unauthorized
    end
  end
end
