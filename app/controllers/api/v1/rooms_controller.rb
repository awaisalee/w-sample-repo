class Api::V1::RoomsController < Api::ApiController
  before_action :find_room, only: [:update, :show, :destroy, :save_room]

  def index
    render json: current_user.rooms, status: 200
  end

  def show
    render json: @room, status: 200
  end

  def update
    @room.update(room_params)
    @room.room_settings = room_security_params(JSON.parse(@room.room_settings))
    if @room.save
      render json: @room, status: 200
    else
      render json: { error: @room.errors.full_messages.join }, status: 403
    end
  end

  def create
    @room = current_user.rooms.create(room_params)
    @room.room_settings = room_security_params(JSON.parse(@room.room_settings))
    if @room.save
      render json: @room, status: 200
    else
      render json: { error: @room.errors.full_messages.join }, status: 403
    end
  end

  def destroy
    if @room == @room.owner.main_room
      render json: { error: I18n.t("room.delete.home_room") }, status: 403
    elsif @room.destroy!
      render json: { success: I18n.t("room.delete.success") }, status: 200
    else
      render json: { error: I18n.t("room.delete.fail", error: @room.errors.full_messages.join) }, status: 403
    end
  end

  def save_room
    @saved_room = current_user.recent_rooms.find_or_create_by(room_id: @room.id)
    if @saved_room.update(recent_room_params)
      render json: { success: "Saved successfully" }, status: 200
    else
      render json: { error: @saved_room.errors.full_messages.join }, status: 403
    end
  end

  private

  def find_room
    # @room = Room.includes(:owner).find_by(uid: params[:room_uid])
    @room = Room.find_by(id: params[:room_uid])
    render json: { error: "Room not found" }, status: 404 unless @room
  end

  def room_params
    params.require(:room).permit(
    :id,
      :name,
      :uid,
      :access_code,
      :security
    )
  end

  def room_security_params settings
    {
      "muteOnStart": params[:room][:mute_on_join].present? ? params[:room][:mute_on_join] == "1" : settings["muteOnStart"],
      "requireModeratorApproval": params[:room][:require_moderator_approval].present? ? params[:room][:require_moderator_approval] == "1" : settings["requireModeratorApproval"],
      "anyoneCanStart": params[:room][:anyone_can_start].present? ? params[:room][:anyone_can_start] == "1" : settings["anyoneCanStart"],
      "joinModerator": params[:room][:all_join_moderator].present? ? params[:room][:all_join_moderator] == "1" : settings["joinModerator"],
      "recording": params[:room][:recording].present? ? params[:room][:recording] == "1" : settings["recording"],
      "authMandatory": params[:room][:auth_mandatory].present? ? params[:room][:auth_mandatory] == "1" : settings["authMandatory"],
      "authMultiFactor": params[:room][:auth_multi_factor].present? ? params[:room][:auth_multi_factor] == "1" : settings["authMultiFactor"],
      "authLobby": params[:room][:auth_lobby].present? ? params[:room][:auth_lobby] == "1" : settings["authLobby"],
      "authOneTimeInviteLink": params[:room][:auth_one_time_invite_link].present? ? params[:room][:auth_one_time_invite_link] == "1" : settings["authOneTimeInviteLink"],
      "webinarMode": params[:room][:webinar_mode].present? ? params[:room][:webinar_mode] == "1" : settings["webinarMode"]
    }.to_json
  end

  def recent_room_params
    params.require(:recent_room).permit(
      :saved,
      :last_joined_at
    )
  end
end
