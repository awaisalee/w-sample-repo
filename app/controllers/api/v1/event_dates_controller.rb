class Api::V1::EventDatesController < Api::ApiController
#   before_action :find_event, only: [:update, :show, :destroy]
#   skip_before_action :authenticate_request, only: [:index, :show]

  def create
    @event_date = EventDate.new(event_date_params)
    if @event_date.save
      render json: @event_date, status: 200
    else
      render json: { error: @event_date.errors.full_messages.join }, status: 403
    end
  end

  private

  def event_date_params
    params.require(:event_date).permit(
     :start_date,
     :start_time,
     :end_date,
     :end_time,
     :event_id
    )
  end
end
