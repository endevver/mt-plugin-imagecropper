# Image Cropper Plugin for Movable Type #

The Image Cropper Plugin provides a simple user interface for managing and
generating custom thumbnails from your image assets.

The plugin was specifically designed to addressed the case where publishers
want the ability to produce different thumbnails designed specifically for
certain different locations on a web site. Furthermore, for each of these
locations it is not sufficient simply to scale the asset in question; rather
the publisher would rather crop the asset in a custom manner for each thumbnail
generated.

Finally, in order to properly annotate thumbnails to credit the photographer
and preserve any required copyright notices, this plugin allows you place some
text on the image accordingly.

This utility facilitates that process.

## Requirements ##

* Movable Type 5.1 or greater
* Movable Type 6.x

Movable Type 4.x is supported with [version 1.1.3](https://github.com/endevver/mt-plugin-imagecropper/releases/tag/v1.1.3).

## Features ##

* Define a set of "prototypes" which in essence are a prescribed set of
  allowable thumbnail sizes.

* Manage all related thumbnails from a single dashboard.

* Create alternate thumbnails using a simple drag-and-drop cropping interface
  -- without ever leaving Movable Type.

* Automatically create thumbnails based on prototypes for allowable image sizes.

* Annotate thumbnails with a custom message.

* Place annotations using the orientation and location you specify on the
  generated thumbnail.

* Hooks for designers to define thumbnail prototypes for their themes and
  template sets so that their users don't have to.

## Installation ##

To install this plugin follow the instructions found here:

http://tinyurl.com/easy-plugin-install

## Usage ##

### Managing "Prototypes" ###

To manage the list of allowable cropped thumbnails for your web site, select
"Thumbnail Prototypes" from the Preferences menu from within Movable Type.

Then simply add and edit thumbnail prototypes by defining the following
properties for each:

* Max Width
* Max Height
* Label (used later for selecting and placing cropped images on your web site)
* AutoCrop

AutoCrop's yes/no property belies greater capability. A prototype with AutoCrop
enabled will automatically crop and scale the image to the desired size. This
happens under several conditions:

* When the image is first uploaded. An AutoCrop job is added to the Publish
  Queue where it will be processed as soon as possible. Hopefully, when you are
  ready to insert an image into your Entry, for example, a new asset based on
  the AutoCrop prototype is ready for you to use!

* From the Manage Assets or Edit Asset screen you can use the Automatically
  Generate Thumbnails option to create a job in the Publish Queue to build any
  AutoCrop-enabled prototypes.

* When publishing a template, if an asset with the desired prototype can not be
  found *and* if the desired prototype is AutoCrop-enabled, a job will be added
  to the Publish Queue.

Additionally, when publishing, if no asset can be found for the desired
AutoCrop-enabled prototype then a dynamic URL can be returned instead of the
expected asset URL. (Enale the `use_dynamic_url` argument, described below.)
When hitting this dynamic URL -- such as when visiting a page that has an image
tag with the `src` property set to the dynamic URL -- Image Cropper will insert
a job into the Publish Queue if an AutoCrop-enabled prototype is found, and
will also republish the desired page after the new cropped assets have been
created.

It's also worth pointing out that AutoCrop won't overwrite any existing
thumbnails, which is particularly important if you've gone to the trouble of
creating a manual crop already!

### Managing Thumbnails ###

Once you have defined a list of prototypes you can begin creating thumbnails.
To do that, navigate to the Edit Asset screen associated with the asset in
question. In the sidebar you will see a link called "Generate Thumbnails."
Clicking that link will take you to the cropping dashboard.

### Adding Cropped Images to your Website ###

Once you have created a cropped thumbnail, you can display it on your web site
using the following template code:

    <mt:Asset id="136">
      <mt:CroppedAsset label="Square">
        <img src="<mt:AssetURL>" />
      </mt:CroppedAsset>
    </mt:Asset>

It is quite possible however that you need to display the cropped version of an
asset only if it is available and fall back to a simple scaled version of the
thumbnail if a cropped version cannot be found. The following template code
shows how you can use `<mt:else>` to do just that:

    <mt:Asset id="136">
      <mt:CroppedAsset label="Square">
        <img src="<mt:AssetURL>" width="100" height="100" />
      <mt:Else>
        <img src="<mt:AssetThumbnailURL square="1" width="100">" />
      </mt:CroppedAsset>
    </mt:Asset>

## Config Directives ##

* **`DefaultCroppedImageText`** - Determines the default text to be used when
  annotating images.

## Template Tags ##

* `<mt:DefaultCroppedImageText>` - Returns the default cropped image text as
  specified by the DefaultCroppedImageText config parameter.

* `<mt:CroppedAsset>` - Places the desired cropped image asset into context.
  This tag must be called with an existing asset (the parent asset) already in
  context. See example above. Allowable arguments:

  * `label` - The label to filter by.
  * `no_autocrop` - Use this argument when a prototype has autocrop enabled but
    no thumbnail is available to ensure that *some* asset is returned.
    Effectively, this is like using the "Else" in the CroppedAsset tag. Set to
    `0` by default; enable with `1`.
  * `use_dynamic_url` - Use this argument to generate a dynamic URL for assets
    that use a prototype with autocrop enabled but no thumbnail is yet created.
    As described above, the dynamic URL will return an asset, insert an
    AutoCrop worker, and insert a republish worker to eliminate the use of the
    dynamic URL. It is also worth noting that the dynamic URL can cause a
    significant load on the server, particularly when many thumbnails from
    AutoCrop-enabled prototypes are requested. This feature works best when you
    know that only a few assets are going to be needed at a given time.

## Designer Guide ##

The Image Cropper plugin exposes a simple set of hooks that can be embedded in
a theme's `config.yaml` file so that designers can specify the exact dimensions
of their fixed image prototypes. When prototypes are defined in this way, they
will appear automatically on the **Preferences > Thumbnail Prototypes** screen
for blogs using the corresponding theme.

To define thumbnail prototypes via `config.yaml`, consult this super 
simple example:

    generic_blog_theme:
      label: 'Generic Blog Theme'
      thumbnail_prototypes:
        feature_thumb:
          label: 'Featured Thumbnail'
          max_width: 100
          max_height: 90
        feature_lrg:
          label: 'Homepage Feature'
          max_width: 350
          max_height: 300
      templates:
        index:
          etc...

As you can see you can define one or more prototypes easily for a theme.
Designers can specify the label for the prototype as well as its dimensions.

## Help, Bugs and Feature Requests ##

If you are having problems installing or using the plugin, please check out our general knowledge base and help ticket system at [help.endevver.com](http://help.endevver.com).

If you know that you've encountered a bug in the plugin or you have a request for a feature you'd like to see, you can file a ticket in [Github Issues](https://github.com/endevver/mt-plugin-imagecropper/issues).

## Copyright ##

This plugin was created from the kind support of 
Talking Points Memo (http://www.talkingpointsmemo.com/), who
supports and appreciates open source. We <3 TPM.

Copyright 2009, Endevver, LLC. All rights reserved.

## License ##

This plugin is licensed under the GPL v2.

# About Endevver #

We design and develop web sites, products and services with a focus on 
simplicity, sound design, ease of use and community. We specialize in 
Movable Type and offer numerous services and packages to help customers 
make the most of this powerful publishing platform.

http://www.endevver.com/

