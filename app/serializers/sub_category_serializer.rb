class SubCategorySerializer < ActiveModel::Serializer
  attributes :id, :title, :description, :is_active

  belongs_to :category
end
