
module Calendar
  extend ActiveSupport::Concern

  def get_ical(appointment, organizer, attendee, room_url, room_code, action=nil)
    cal = Icalendar::Calendar.new
    cal.prodid = "Wistleroom"
    method = action == 'drop' ? 'CANCEL' : 'REQUEST'
    cal.append_custom_property("METHOD", method)
    participants = appointment.participants.pluck(:email).push(organizer.email)
    cal.event do |e|
      e.append_custom_property("DTSTART", appointment.start_date.utc.strftime("%Y%m%dT%H%M%SZ"))
      e.append_custom_property("DTEND", appointment.end_date.utc.strftime("%Y%m%dT%H%M%SZ"))
      e.summary = appointment.name
      e.ip_class = "PRIVATE"
      e.organizer = Icalendar::Values::CalAddress.new("mailto:noreply@letswhistle.io", cn: "#{organizer.try(:full_name)} via Whistle")
      cal_attendees = []
      participants.map do |participant|
        cal_attendees.push(Icalendar::Values::CalAddress.new(
          "mailto:#{participant}",
          cutype: true,
          role: "REQ-PARTICIPANT",
          parstat: "NEEDS-ACTION",
          rsvp: true,
          cn: "#{participant}"
        ))
      end
      e.attendee = cal_attendees
      sequence = action == 'drop' ? "2" : "1"
      e.append_custom_property("SEQUENCE", sequence)
      status = action == 'drop' ? "CANCELLED" : "TENTATIVE"
      e.append_custom_property("STATUS", status)
      e.append_custom_property("TRANSP", "OPAQUE")
      e.url = room_url
      e.location = room_url
      e.description = "Click the link below to join the session <br>Link: <a href='#{room_url}'>#{room_url}</a> <br>#{'Room key: '+room_code if room_code.present? }".html_safe
      e.uid = appointment.id.to_s
    end

    cal.to_ical

  end
end
