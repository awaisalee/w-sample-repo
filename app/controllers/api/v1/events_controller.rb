class Api::V1::EventsController < Api::ApiController
  before_action :find_event, only: [:update, :show, :destroy]
  skip_before_action :auth0_authenticate_request!, only: [:index, :show]

  def index
    @events = Event.all

    render json: @events, status: 200
  end

  def show
    render json: @event, status: 200
  end

  def update
    if @event.update(event_params)
      render json: @event, status: 200
    else
      render json: { error: @event.errors.full_messages.join }, status: 403
    end
  end

  def create
    @event = Event.new(event_params)
    if @event.save
      render json: @event, status: 200
    else
      render json: { error: @event.errors.full_messages.join }, status: 403
    end
  end

  def destroy
    if @event.destroy
      render json: {}, status: 204
    else
      render json: { error: @event.errors.full_messages.join }, status: 403
    end
  end

  private

  def find_event
    @event = Event.find_by(id: params[:id])
    render json: { error: "Event not found" }, status: 404 unless @event
  end

  def event_params
    params.require(:event).permit(
      :subject,
      :description,
      :timezone,
      :category_id,
      :sub_category_id,
      :room_id,
      :event_type,
      :security,
      :pricing_type,
      :price,
      :webinar_mode,
      :recurrence,
      :recurrence_type,
      :recurrence_end_type,
      :recurrence_end_date,
      :recurrence_days,
      :recurrence_meetings,
      :limited_slots,
      :no_of_slots,
      :is_private,
      :allow_participants_to_share,
      :mute_participants,
      event_dates_attributes: [
        :id,
        :_destroy,
        :start_date,
        :end_date
      ],
      event_moderators_attributes: [
        :id,
        :_destroy,
        :moderator_id,
        :name,
        :email
      ],
      event_invitees_attributes: [
        :id,
        :_destroy,
        :name,
        :email,
        :invitee_id
      ],
      event_speakers_attributes: [
        :id,
        :_destroy,
        :speaker_id,
        :email,
        :name,
        :title,
        :twitter_handle,
        :instagram_handle
      ]
    )
  end
end
