# settings
BOOTSTRAP_THEME = ENV['BOOTSTRAP_THEME'] || '//netdna.bootstrapcdn.com/bootswatch/2.3.0/journal/bootstrap.min.css'
FORUM_NAME = ENV['FORUM_NAME'] || 'EasyForum'
WHITELIST = (ENV['WHITELIST'].nil? || ENV['WHITELIST'].empty? ? [] : ENV['WHITELIST'].split(','))

# helper module
module EasyHelper
  include DataMapper::Inflector
  def markdown(content)
    Redcarpet::Markdown.new(Redcarpet::Render::HTML, autolink: true, space_after_headers: true).render(content)
  end
  
  def snippet(page, options={})
    haml page, options.merge!(layout: false)
  end
    
  def toolbar
    haml :toolbar, layout: false
  end
  
  def must_login
    raise "You have not signed in yet. Please sign in first!" unless session[:user]
    true
  end
  
  def must_in_whitelist
    raise "No one in the whitelist yet." if WHITELIST.empty?
    raise "You are not allowed to do this." unless WHITELIST.include?(session[:user]['username'])
    true
  end
  
  def get_parent(clazz)
    relationship = clazz.relationships.find {|r| r.kind_of?(DataMapper::Associations::ManyToOne::Relationship)}
    relationship.nil? ? nil : relationship.parent_model
  end

  def get_child(clazz)
    relationship = clazz.relationships.find {|r| r.kind_of?(DataMapper::Associations::OneToMany::Relationship)}
    relationship.nil? ? nil : relationship.child_model
  end
  
  
end

# models
DataMapper.setup(:default, ENV['DATABASE_URL'])

class Forum
  include DataMapper::Resource
  property :id, Serial
  property :created_at, DateTime
  property :heading, String, length: 255
  property :content, Text
  property :user_pic_url, URI
  property :user_name, String
  property :user_link, String  
  property :user_facebook_id, String
  
  has n, :topics, constraint: :destroy
  
  def is_owned_by(user)
    self.user_facebook_id == user['id']
  end  
end

class Topic
  include DataMapper::Resource
  property :id, Serial
  property :created_at, DateTime
  property :heading, String, length: 255
  property :content, Text
  property :views, Integer, default: 0
  property :user_pic_url, URI
  property :user_name, String
  property :user_link, String  
  property :user_facebook_id, String
  
  belongs_to :forum
  has n, :posts, constraint: :destroy
  
  def is_owned_by(user)
    self.user_facebook_id == user['id']
  end  
end

class Post
  include DataMapper::Resource
  property :id, Serial
  property :created_at, DateTime
  property :heading, String, length: 255
  property :content, Text
  property :user_pic_url, URI
  property :user_name, String
  property :user_link, String  
  property :user_facebook_id, String
  
  belongs_to :topic
  
  def is_owned_by(user)
    self.user_facebook_id == user['id']
  end
end
DataMapper.finalize

# configure Sinatra
configure do
  enable :sessions
  enable :inline_templates
  set :session_secret, ENV['SESSION_SECRET'] ||= 'sausheong_secret_stuff'
  set :show_exceptions, false
  
  # installation steps  
  unless DataMapper.repository(:default).adapter.storage_exists?('forum')
    DataMapper.auto_upgrade!     
    Forum.create(heading: "Your first forum", content: "Some description for your first forum", 
                 user_name: 'Forum Owner', user_pic_url: 'http://s3.amazonaws.com/37assets/svn/765-default-avatar.png')
  end
end

helpers EasyHelper

#routes
error RuntimeError do
  @error = request.env['sinatra.error'].message
  haml :error
end

get "/" do
  @forums = Forum.all
  haml :index
end

get "/resource/:obj/view/:id" do
  cl = Kernel.const_get params[:obj].capitalize
  page = params[:page] || 1
  page_size = params[:page_size] || 5  
  @obj = cl.get params[:id].to_i
  child_cl = get_child(cl)
  if child_cl
    @children = @obj.send(pluralize(child_cl.name.downcase).to_sym).all(order: :created_at.desc).page(page: page, per_page: page_size)
  end
  haml params[:obj].to_sym
end

get "/resource/:obj/new" do
  @resource = params[:obj]
  @parent_id = params[:parent_id]
  if @resource == 'forum'
    must_login and must_in_whitelist
  else
    must_login
  end
  cl = Kernel.const_get @resource.capitalize
  @obj = cl.new
  if @parent_id
    @parent = get_parent(cl).get @parent_id
  end
  haml :new
end

get "/resource/:obj/edit/:id" do
  @resource = params[:obj]
  if @resource == 'forum'
    must_login and must_in_whitelist
  else
    must_login
  end
  cl = Kernel.const_get @resource.capitalize
  @obj = cl.get params[:id]
  raise 'Cannot find this object' unless @obj
  haml :edit
end

delete "/resource/:obj" do
  must_login and must_in_whitelist
  cl = Kernel.const_get params[:obj].capitalize
  obj = cl.get params[:id].to_i
  parent_cl = get_parent(cl)
  parent = obj.send(parent_cl.name.downcase.to_sym) if parent_cl
  raise "You didn't write this post so you can't remove it." unless obj.user_facebook_id == session[:user]['id']
  obj.destroy
  if parent_cl
    redirect "/resource/#{parent_cl.name.downcase}/view/#{parent.id}"
  else
    redirect "/"    
  end
end

post "/resource/:obj" do
  must_login
  cl = Kernel.const_get params[:obj].capitalize
  parent_cl = get_parent(cl)
  unless obj = cl.get(params[:id])
    if parent_cl
      @parent = parent_cl.get params[:parent_id]
      obj = @parent.send(pluralize(params[:obj]).to_sym).new
    else
      obj = cl.new
    end
    obj.user_pic_url, obj.user_facebook_id, obj.user_name, obj.user_link = 
      session[:user]['picture']['data']['url'], session[:user]['id'], session[:user]['name'], session[:user]['link']    
  end
  obj.heading, obj.content = params['heading'], params['content']
  obj.save
  if parent_cl
    parent_id = obj.send(parent_cl.name.downcase.to_sym).id
    redirect "/resource/#{parent_cl.name.downcase}/view/#{parent_id}"
  else
    redirect "/"    
  end
end

get '/auth/login' do  
  RestClient.get "https://www.facebook.com/dialog/oauth",
                    params: {client_id: ENV['FACEBOOK_APP_ID'], 
                             redirect_uri: "#{request.scheme}://#{request.host}:#{request.port}/auth/callback"}
end

get '/auth/callback' do
  if params['code']
    resp = RestClient.get("https://graph.facebook.com/oauth/access_token",
                      params: {client_id: ENV['FACEBOOK_APP_ID'],
                               client_secret: ENV['FACEBOOK_APP_SECRET'],
                               redirect_uri: "#{request.scheme}://#{request.host}:#{request.port}/auth/callback",
                               code: params['code']})                                           
    session[:access_token] = resp.split("&")[0].split("=")[1]
    user = RestClient.get("https://graph.facebook.com/me?access_token=#{session[:access_token]}&fields=picture,name,username,link,timezone")
    session[:user] = JSON.parse user
    redirect "/"
  end
end

get "/auth/logout" do
  session.clear
  redirect "/"
end

__END__

@@ layout
!!! 1.1
%html{:xmlns => "http://www.w3.org/1999/xhtml"}
  %head
    %title=FORUM_NAME
    %meta{name: 'viewport', content: 'width=device-width, initial-scale=1.0, maximum-scale=1.0'}
    %link{rel: 'stylesheet', href: BOOTSTRAP_THEME, type: 'text/css'}
    %link{rel: 'stylesheet', href: "//netdna.bootstrapcdn.com/twitter-bootstrap/2.3.1/css/bootstrap-responsive.min.css", type: 'text/css'}
    %link{rel: 'stylesheet', href: '//netdna.bootstrapcdn.com/font-awesome/3.0.2/css/font-awesome.css', type:  'text/css'}
    %link{rel: 'stylesheet', href: '//twitter.github.com/bootstrap/assets/js/google-code-prettify/prettify.css', type:  'text/css'}
    %link{rel: 'stylesheet', href: '//twitter.github.com/bootstrap/assets/css/docs.css', type:  'text/css'}
    %script{type: 'text/javascript', src: "//code.jquery.com/jquery-1.9.1.min.js"}    
    %script{type: 'text/javascript', src: "//netdna.bootstrapcdn.com/twitter-bootstrap/2.3.1/js/bootstrap.min.js"}

  %body
    #fb-root   
    =toolbar
    =yield
    
    %br
    %footer
      %p.mute.footer 
        %small 
          &copy; 
          %a{href:'http://about.me/sausheong'} Chang Sau Sheong 
          2013

:css
  body { font-size: 1.2em; line-height: 1.6em; }
  li {line-height: 1.4em}
  li > a {text-decoration: underline; }
  th.center, td.center {text-align: center;}
  .table td {line-height: 1.4em;}
  textarea, input[type='text'] {font-size: 0.9em;}

@@ toolbar
.navbar.navbar-fixed-top
  .navbar-inner
    .container

      %button.btn.btn-navbar.collapsed{'data-toggle' => 'collapse', 'data-target' => '.nav-collapse'}
        %span.icon-bar
        %span.icon-bar
        %span.icon-bar

      %ul.nav
        %a.brand{href:"/"}
          %i.icon-comments
          =FORUM_NAME

      .nav-collapse        

        %ul.nav.pull-right
          - if session[:user]
            %li.dropdown
              %a.dropdown-toggle{:href => "#", 'data-toggle' => 'dropdown' }
                %i.icon-user
                =session[:user]['name']
                %span.caret
              %ul.dropdown-menu
                %li
                  %a{:href => '/auth/logout'} Sign out
          - else
            %li
              %a{:href => '/auth/login'} 
                %i.icon-facebook-sign
                Sign in

@@ error
%section
  .container.content.center      
    %h1.text-error.text-center
      %i.icon-warning-sign
      Oops, there's been an error. 
    %br
    %p.lead.text-center
      =@error

@@ index
%section
  .container.content
    .row
      .span12
        %ul.breadcrumb
          %li Index
      
      - if session[:user] and WHITELIST.include?(session[:user]['username'])
        .span12
          %a.btn{href: '/resource/forum/new'} 
            %i.icon-plus-sign-alt
            New forum      
          
      .span12
        %br
        %table.table.table-hover
          %thead
            %th.span6 Forum
            %th.span1.center Topics
            %th.span1.center Posts
            %th.span4 Last Post
          %tbody
            - @forums.each do |forum|
              %tr
                %td
                  %h4.text-info
                    %a{href: "/resource/forum/view/#{forum.id}"}
                      %i.icon-comments
                      =forum.heading                  
                  %p
                    =markdown forum.content            
                %td.center
                  %small
                    #{forum.topics.size}
                %td.center
                  %small
                    #{forum.topics.posts.size}
                %td
                  - if forum.topics.posts.last
                    by
                    %a{href:forum.topics.posts.last.user_link}=forum.topics.posts.last.user_name
                    %a{href:"/resource/topic/view/#{forum.topics.posts.last.topic.id}"}
                      %i.icon-share
                    %br
                    %small
                      =forum.topics.posts.last.created_at.strftime "%e %b %Y, %l:%M %P"
                  - else
                    No posts yet

@@ forum
%section
  .container.content
    .row
      .span12
        %ul.breadcrumb
          %li 
            %a{href: "/"} Index
            %span.divider /
          %li.active=@obj.heading
            
      .span12
        %h3
          %i.icon-comments
          =@obj.heading
          - if session[:user] and @obj.is_owned_by(session[:user])
            %span
              %small.muted
                %form#delete{method: 'post', action: '/resource/forum'}
                  %input{type: 'hidden', name: 'id', value: @obj.id}
                  %input{type: 'hidden', name: '_method', value: 'delete'}
                  %a{href:"/resource/forum/edit/#{@obj.id}"}
                    %i.icon-pencil
                    edit
                  &middot;
                  %a{href:"#", onclick: "$('#delete').submit();"}
                    %i.icon-remove
                    delete
        - if session[:user]
          %a.btn{href:"/resource/topic/new?parent_id=#{@obj.id}"}
            %i.icon-plus-sign-alt
            New topic
                
      .span12
        %br
        %table.table.table-hover
          %thead
            %th.span6 Topics
            %th.span1.center Replies
            %th.span1.center Views
            %th.span4 Last Post
          %tbody
            - @children.each do |topic|
              %tr
                %td
                  %h4
                    %a{href: "/resource/topic/view/#{topic.id}"}
                      %i.icon-comment
                      =topic.heading   
                    %br
                    %small 
                      by 
                      %a{href:"#{topic.user_link}"} #{topic.user_name}
                      &middot; #{topic.created_at.strftime "%e %b %Y, %l:%M %P"}                               
                %td.center
                  %small #{topic.posts.size}
                %td.center
                  %small #{Topic.sum(:views, conditions: ['id = ?', topic.id])} 
                %td
                  - if topic.posts.last
                    by
                    %a{href:topic.posts.last.user_link}=topic.posts.last.user_name
                    %a{href:"/resource/topic/view/#{topic.posts.last.topic.id}"}
                      %i.icon-share
                    %br
                    %small
                      =topic.posts.last.created_at.strftime "%e %b %Y, %l:%M %P"
                  - else
                    No posts yet
        .pagination
          =@children.pager.to_html("/resource/forum/view/#{@obj.id}")

@@ topic
- @obj.update(views: @obj.views + 1)
%section
  .container.content
    .row
      .span12
        %ul.breadcrumb
          %li 
            %a{href: "/"} Index
            %span.divider /
          %li
            %a{href: "/resource/forum/view/#{@obj.forum.id}"}=@obj.forum.heading
            %span.divider /
          %li.active=@obj.heading
    .row         
      .span10
        %h3
          %i.icon-comments
          =@obj.heading          
          - if session[:user] and @obj.is_owned_by(session[:user])
            %span
              %small.muted
                %form#delete{method: 'post', action: '/resource/topic'}
                  %input{type: 'hidden', name: 'id', value: @obj.id}
                  %input{type: 'hidden', name: '_method', value: 'delete'}
                  %a{href:"/resource/topic/edit/#{@obj.id}"}
                    %i.icon-pencil
                    edit
                  &middot;
                  %a{href:"#", onclick: "$('#delete').submit();"}
                    %i.icon-remove
                    delete
        .media
          %a.pull-left{href:'#'}
            %img.media-object{src: @obj.user_pic_url}
          .media-body
            =markdown @obj.content
        .span12 &nbsp;
        - if session[:user]
          %a.btn{href:"/resource/post/new?parent_id=#{@obj.id}"}
            %i.icon-plus-sign-alt
            Post Reply

      .span12
        %br
        %table.table.table-hover
          %tbody
            - @children.each do |post|
              %tr
                %td.span8
                  %h4
                    %i.icon-comment-alt
                    =post.heading                      
                    - if session[:user] and post.is_owned_by(session[:user])
                      %span
                        %small.muted
                          %form{method: 'post', action: '/resource/post', id: "delete_#{post.id}"}
                            %input{type: 'hidden', name: 'id', value: post.id}
                            %input{type: 'hidden', name: '_method', value: 'delete'}
                            %a{href:"/resource/post/edit/#{post.id}"}
                              %i.icon-pencil
                              edit
                            &middot;
                            %a{href:"#", onclick: "$('#delete_#{post.id}').submit();"}
                              %i.icon-remove
                              delete
                  %p
                    =markdown post.content
                %td.span4
                  .media
                    %a.pull-left{href:'#'}
                      %img.media-object{src: post.user_pic_url}
                    .media-body
                      %h4.media-heading{style: 'margin-bottom: 0'} 
                        %a{href:"#{post.user_link}"} #{post.user_name}                      
                      %small #{post.created_at.strftime "%e %b %Y, %l:%M %P"}
        .pagination
          =@children.pager.to_html("/resource/topic/view/#{@obj.id}")


@@ new
%section
  .container.content
    %h3 
      %i.icon-plus-sign-alt
      Add New #{@resource.capitalize}
    
    .row
      .span12
        %form{method: 'post', action: "/resource/#{@resource}"}
          %p.text-info.lead
            Type #{@resource} information into the fields and click on add to create it.
          =snippet :_fields

          .form-actions
            %input.btn.btn-primary{type: 'submit', value: 'Add'}
            - unless @resource == 'forum'
              %a.btn{href: "/resource/#{@parent.class.name.downcase}/view/#{@parent_id}"} Cancel
            - else
              %a.btn{href: '/'} Cancel
    - if @parent    
      .row
        .span12
          %blockquote
            %h4=@parent.heading
            %p=markdown @parent.content


@@ edit
%section
  .container.content
    %h3 
      %i.icon-plus-sign-alt
      Edit #{@resource.capitalize}
    
    .row
      .span12
        %form{method: 'post', action: "/resource/#{@resource}"}
          %p.text-info.lead
            Modify your #{@resource} below.
          =snippet :_fields
          %input{type: 'hidden', name: 'id', value: @obj.id}
          .form-actions
            %input.btn.btn-primary{type: 'submit', value: 'Modify'}
            %a.btn{href:'#', onclick: 'history.back();return false;'} Cancel

@@ _fields
%fieldset
  %input.span8{type: 'text', name: 'heading', placeholder: "Type your #{@resource} heading here", value: @obj.heading}
  %textarea.span8{name: 'content', placeholder: "Type your #{@resource} content here", rows: 10}
    =@obj.content
    
- if @parent_id
  %input{type: 'hidden', name: 'parent_id', value: @parent_id}    
