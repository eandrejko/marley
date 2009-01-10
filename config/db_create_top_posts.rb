# Inspired by Ryan Tomayko, http://github.com/rtomayko/wink/tree/master/lib/wink/models.rb#L276
ActiveRecord::Schema.define(:version => 2) do
  create_table :top_posts do |t|
    t.string :post_id, :null => false
    t.integer :count, :default => 0
  end
  add_index :top_posts, :post_id
  add_index :top_posts, :count
end