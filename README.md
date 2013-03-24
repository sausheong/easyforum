# EasyForum

A minimalist forum web application for Rubyists. All source code (everything) is in a single ~500 line-of-code file.

Now you can install EasyForum into Heroku in just 3 steps!

1. Sign up for a Heroku account
2. Register a Facebook app
3. Run the installation script and follow the instructions

## Features

* Simplified 3-level discussion mechanism - Forums -> Topics -> Posts
* Authentication through Facebook sign in
* Only authenticated users can contribute to EasyForum
* Only authenticated users in a whitelist can create a new forum
* Only the author of a forum/topic/post can delete it
* Write topics and posts in Markdown syntax
* Easy 3-step installation script

## How to install on Heroku

You need these few things.

### A Heroku account

You will need to sign up for a Heroku account. If you are using the installation script, you will need to get the Heroku API key from https://dashboard.heroku.com/account before you start using the script.

### Facebook app

EasyForum integrates with Facebook for authentication. Create a Facebook app through http://developers.facebook.com. Then look out for the *App ID* and *App Secret*. If you are using the installation script, you will be asked for these two pieces of information. Please remember to set your Facebook app to integrate with your wiki through 'Website with Facebook Login', with the Site URL set to http://[your app name].herokuapp.com:80/

If you have entered the wrong ID and secret, you can set them again. Use the values to set the environment variables *FACEBOOK_APP_ID* and *FACEBOOK_APP_SECRET* accordingly.

Don't like Facebook? Deal with it, or modify it to integrate with what you like or write your own authentication mechanism. Simply change the `/auth/login` route and there you go.

  
## Whitelist of authors

By default anyone can contribute to the forum, as long as they authenticate themselves first (with Facebook). However only people in the whitelist of users can create new forums. Set the environment variable `WHITELIST` to a comma-delimited list of Facebook usernames (no spaces before or after the comma please). If you want to be the only one who can write, just put in your Facebook username. For eg. my Facebook username is 'sausheong' so that's the `WHITELIST` setting for me if I want only myself to be able create new forums.

## Other settings

Only the Facebook account is really needed, everything else is optional. Here are some other environment variables you might want to set:

* `BOOTSTRAP_THEME` - A URL to the Bootstrap CSS stylesheet you want to use instead of the default. I used the *Journal* theme from Bootswatch. The default is the default Bootstrap stylesheet
* `FORUM_NAME` - A string to name your forum. The default is 'EasyForum'  

## To set environment variables in Heroku

Add the configuration settings using `heroku config:add <env variable>=<value>`. For a fuller explanation please refer to https://devcenter.heroku.com/articles/config-vars
  
## Installing on Heroku

The fastest way to install is to run the installation script and follow the instructions.
    
    > ruby ./install.rb
    
Then enter the Heroku API key, Facebook App ID, App Secret and whitelist when asked. At the end of the script you will be provided with your new forum!