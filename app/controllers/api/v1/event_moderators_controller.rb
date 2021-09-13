class Api::V1::EventModeratorsController < Api::ApiController
  #   before_action :find_event, only: [:update, :show, :destroy]
  #   skip_before_action :authenticate_request, only: [:index, :show]
    
  def create
    @event_moderator = EventModerator.new(event_moderator_params)
    if @event_moderator.save
      render json: @event_moderator, status: 200
    else
      render json: { error: @event_moderator.errors.full_messages.join }, status: 403
    end
  end

  private

  def event_moderator_params
    params.require(:event_moderator).permit(
      :event_id,
      :moderator_id,
      :name,
      :email
    )
  end
end
