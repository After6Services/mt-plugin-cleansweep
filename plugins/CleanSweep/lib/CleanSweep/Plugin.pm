# Good for Nothing Plugin for Movable Type
# Author: Byrne Reese
# Copyright (C) 2008 Six Apart, Ltd.
# This file is licensed under the GPL.

package CleanSweep::Plugin;

use strict;
use warnings;

sub blogconf_template {
    my ($plugin,$param,$scope) = @_;
    my $app = MT::App->instance;
    my $script = $app->{cfg}->CGIPath . $app->{cfg}->AdminScript;
    my $blog_id = $app->blog->id;
    my $url = $app->blog->site_url;
    $url =~ s!https?://[^/]*!!i;
    $script =~ s!https?://[^/]*!!i;

    my $tmpl = <<EOT;
    <mtapp:Setting
        id="404-url"
        label="404 URL"
        hint="Enter the URL to redirect the user to when a resource cannot be found."
        show_hint="1">
        <p><input type="text" size="50" name="404url" value="<mt:Var name="404url">" /></p>
    </mtapp:Setting>

    <mtapp:Setting
        id="webserver"
        label="Web Server">
        <div style="margin-bottom: 15px;">
            <input type="radio"
                name="webserver"
                id="webserver-apache"
                value="apache"
                onclick="show('apache-config'); hide('lighttpd-config');"
                <mt:if name="webserver" eq="apache">checked</mt:if> />
            <label for="webserver-apache">Apache</label>
            <input type="radio"
                name="webserver"
                id="webserver-lighttpd"
                value="lighttpd"
                onclick="show('lighttpd-config'); hide('apache-config');"
                <mt:if name="webserver" eq="lighttpd">checked</mt:if> />
            <label for="webserver-lighttpd">Lighttpd</label>
        </div>

        <div id="apache-config"
            style="<mt:if name="webserver" ne="apache">display:none;</mt:if>">
            <p>Add this to your Apache configuration file:</p>
            <pre><code>&lt;Location $url&gt;
    ErrorDocument 404 $script?__mode=404&blog_id=$blog_id
&lt;/Location&gt;</code></pre>
        </div>
        <div id="lighttpd-config"
            style="<mt:if name="webserver" ne="lighttpd">display:none;</mt:if>">
            <p>Add this to your Lighttpd configuration file:</p>
            <pre><code>server.error-handler-404 = "$script?__mode=404&blog_id=$blog_id"</code></pre>
        </div>
    </mtapp:Setting>

    <mtapp:Setting
        id="file-types"
        label="Valid File Types"
        hint="Enter a comma-separated list of file types that Clean Sweep should try to redirect."
        show_hint="1">
        <input type="text"
            name="file_types"
            id="file_types"
            value="<mt:Var name="file_types">" />
    </mtapp:Setting>

EOT
    $tmpl;
}

1;
