class CategorySerializer < ActiveModel::Serializer
  attributes :id,
             :title,
             :description,
             :is_active

  has_many :sub_categories
end
