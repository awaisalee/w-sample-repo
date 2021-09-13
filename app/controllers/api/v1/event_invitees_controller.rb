class Api::V1::EventInviteesController < Api::ApiController
  #   before_action :find_event, only: [:update, :show, :destroy]
  #   skip_before_action :authenticate_request, only: [:index, :show]
    
  def create
    @event_invitee = EventInvitee.new(event_invitees_params)
    if @event_invitee.save
      render json: @event_invitee, status: 200
    else
      render json: { error: @event_invitee.errors.full_messages.join }, status: 403
    end
  end

  private

  def event_invitees_params
    params.require(:event_invitee).permit(
      :event_id,
      :invitee_id,
      :name,
      :email
    )
  end
end
