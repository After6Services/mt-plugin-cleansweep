# Clean Sweep Plugin For Movable Type and Melody

By: Byrne Reese <byrne at majordojo dot com>

Donated in whole to the Movable Type Open Source Project
Copyright 2007-2008 Six Apart Ltd. 

# Overview

CleanSweep is a plugin that assists administrators in finding and fixing
broken inbound links to their website. It was built to support three use
cases:

* to help users monitor any broken links on their blog and have a system that
  can automatically adapt by redirecting stale and inbound links to the proper
  destination.

* to help users get a clean start with their blog by allowing them to
  completely restructure their permalink URL structure and have a system that
  can automatically adapt by redirecting stale and inbound links to the proper
  destination.

* to help users in the process of migrating to Movable Type who are forced to
  modify their web site's URL and permalink structure.

These use cases have to do with preserving a site's page rank in light of a
major redesign.

After configuration, Clean Sweep will track all inbound links that result in a
404 and will ultimately deduce the intended file and redirect the client to
that file.

Clean Sweep will also produce a set of Apache mod_rewrite rules to map inbound
links to their destination permanently.


# Prerequisites

* Movable Type 4.x or Melody 1.x
* [Melody Compatibility
  Layer](https://github.com/endevver/mt-plugin-melody-compat/downloads/)
  (required for users of Movable Type only)


# Configuration

To install this plugin follow the instructions found here:

http://tinyurl.com/easy-plugin-install

Clean Sweep supports both Apache and Lighttpd. For now you elect what web
server you are using on a blog-by-blog basis. All documentation however,
refers to Apache, as it is far more common. Lighttpd users should simply
follow the analogous instruction for their web server when appropriate.

Create a page in Movable Type called "URL Not Found". Give it a basename of
"404". Place whatever personalized message you want that will be displayed to
your visitors when Clean Sweep is unsuccessful in mapping the request to the
correct page or destination. Publish the page and remember the complete URL to
this page on your published blog. (Alternatively, create an Index template for
your 404.)

Navigate to the Plugin Settings area for Clean Sweep. Enter the full URL to
your "URL Not Found" page (as created above) into the "404 URL" configuration
parameter.

Also in the Plugin Settings area, make note of the Apache configuration
directive and place it in your `httpd.conf` or in an `.htaccess` file. Restart
the web server, if necessary.


# Use

Clean Sweep will use the following ruleset in trying to guess the target URL
the client is requesting:

1. Is the target resource using the entry id as a URL? This is a prevalent URL
pattern for older MT installations. This will:

       Map: http://www.majordojo.com/archives/000675.php
       To:  http://www.majordojo.com/205/07/goodbye-bookque.php

2. Is the target resource using underscores when it should be using hyphens?
Many users have switched to using hyphens for purported SEO benefits. This
will attempt to look for a file in the system of the same name, but using '-'
instead of '_'. This will:

       Map: http://www.majordojo.com/2005/07/goodbye_bookque.php
       To:  http://www.majordojo.com/2005/07/goodbye-bookque.php

3. Is their a target resource with the same basename somewhere? If a user
switches their primary mapping to use a date based URL as opposed to a
category based URL, then this rule will apply. This will:

       Map: http://www.majordojo.com/personal-projects/goodbye-bookque.php
       To:  http://www.majordojo.com/2005/07/goodbye-bookque.php

If Clean Sweep was unable to redirect the request it will return the 404 "URL
Not Found" page created above, and logs the 404. You can review all of the
logged 404s by visiting Manage > Logged 404s.

On the Logged 404s screen are options to mange the 404s, including the ability
to specify how a given URL should be handled. Click "Map" to adjust this in a
popup dialog, where you can select:

* Redirect to URL: specify a URL to redirect to as a 301 Redirect response.
* Resource Permanently Removed: returns a 410 Gone response.
* Resource Forbidden: returns a 403 Forbidden response.

Additionally on the Map dialog is a table of referrers. Note that a referring
URL is not available for every URL.

Once a URL has been mapped it is no longer counted. This is useful because
after mapping you can use the Reset function (on the Manage > Logged 404s
page) to delete the count of occurrences for that URL. After manually fixing a
reported URL you can Reset it, and the effect is that new broken URLs will be
quickly visible even after having only two or three hits.



# License

Clean Sweep is licensed under the GPL (v2).
