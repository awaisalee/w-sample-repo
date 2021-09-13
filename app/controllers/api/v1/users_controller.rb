class Api::V1::UsersController < Api::ApiController
  before_action :find_user, only: [:show, :destroy]

  def index
    @users = User.all
    @users = @users.where("email LIKE ?", "%#{params[:email]}%") if params[:email].present?

    render json: @users, status: 200
  end

  def show
    render json: @user, status: 200
  end

  private
  def find_user
    @user = if params[:id] == "me"
      current_user
    else
      User.find(params[:id])
            end
    return render json: { error: "user not found" }, status: 404 unless @user
  end
end
