class Api::V1::UserProfilesController < Api::ApiController
  before_action :find_user_profile, only: [:update, :show, :destroy]

  def get_current_user
    render json: current_user, status: 200
  end

  def create
    @user_profile = UserProfile.new(user_profile_params)
    if @user_profile.save
      render json: @user_profile, status: 201
    else
      render json: { error: @user_profile.errors.full_messages.join }, status: 403
    end
  end

  def update
    if @user_profile.update(user_profile_params)
      render json: @user_profile, status: 200
    else
      render json: { error: @user_profile.errors.full_messages.join }, status: 403
    end
  end

  def show
    render json: @user_profile, status: 200
  end

  def destroy
    if @user_profile.destroy
      render json: { }, status: 204
    else
      render json: { error: @user_profile.errors.full_messages.join }, status: 403
    end
  end

  private

  def find_user_profile
    @user_profile = UserProfile.find_by(id: params[:id])
    return render json: { error: "user profile not found" }, status: 404 unless @user_profile
  end

  def user_profile_params
    params.require(:user_profile).permit(
      :name,
      :status,
      :bio,
      :category_id,
      :user_id,
      :facebook_handle,
      :instagram_handle,
      :twitter_handle,
      :youtube_handle,
      :discord_handle,
      :twitch_handle,
      :telegram_handle
    )
  end
end
