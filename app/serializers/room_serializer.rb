class RoomSerializer < ActiveModel::Serializer
  attributes :id, :name, :uid, :bbb_id, :room_settings, :access_code, :deleted, :security
  belongs_to :owner
end
