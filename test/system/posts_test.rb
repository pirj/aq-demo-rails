require "application_system_test_case"

class PostsTest < ApplicationSystemTestCase
  setup do
    @post = posts(:one)
  end

  test "visiting the index" do
    visit posts_url
    assert_selector "h1", text: "Posts"
  end

  test "creating a Post" do
    visit posts_url
    click_on "New post"

    fill_in "Body", with: "demo body"
    fill_in "Title", with: "demo title"
    click_on "Create Post"

    assert_text "Post was successfully created"
  end

  test "viewing a Post" do
    visit post_url(@post)
    assert_text @post.title
    assert_text @post.body
  end
end
