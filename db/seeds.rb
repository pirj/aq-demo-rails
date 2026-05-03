# Seed enough records that db:seed has measurable wall clock.
users = 5.times.map { |i| User.create!(name: "User #{i}", email: "user#{i}@example.com") }
categories = 4.times.map { |i| Category.create!(title: "Category #{i}", description: "Desc #{i}") }
tags = 8.times.map { |i| Tag.create!(name: "tag-#{i}") }

50.times do |i|
  post = Post.create!(
    title: "Post #{i}",
    body: "Body of post #{i}. " * 20,
    user: users.sample,
    category: categories.sample,
    slug: "post-#{i}",
    published_at: Time.now - i.hours
  )
  3.times do |j|
    Comment.create!(post: post, body: "Comment #{j} on post #{i}.")
  end
end
puts "Seeded #{User.count} users, #{Category.count} categories, #{Tag.count} tags, #{Post.count} posts, #{Comment.count} comments."
