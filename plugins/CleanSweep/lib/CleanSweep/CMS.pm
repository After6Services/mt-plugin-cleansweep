#!/usr/bin/perl -w
#
# This software is licensed under the Gnu Public License, or GPL v2.
# 
# Copyright 2007, Six Apart, Ltd.

package CleanSweep::CMS;

use strict;
use warnings;
use base qw( MT::App );
use MT::Util qw( encode_html format_ts offset_time_list relative_date );

# When a server returns a 404, try to handle it intelligently: use a redirect,
# if set, try to find a likely intended URL, or return the custom 404 page.
# Lastly, log the 404.
sub report {
    my $app  = shift;
    my $q    = $app->can('query') ? $app->query : $app->param;
    my $blog = $app->blog
        if $app->can('blog');
    $blog = $app->model('blog')->load( $q->param('blog_id') )
        if !$blog && $q->param('blog_id');
    die $app->error('Blog ID not specified!') if !$blog;

    my $plugin = $app->component('CleanSweep');
    my $config = $plugin->get_config_hash('blog:'.$blog->id);
    my $redirect = $config->{'404url'};

    # If this URL isn't in the valid file type list just give up and send the
    # user to the 404 page. No reason to process file types we don't care about.
    # (Clean Sweep really only knows about Entry and Page URLs, so there's
    # likely little reason to try to redirect things like assets, other missing
    # files, or malformed URLs.
    my @file_types = split( ',', $config->{'file_types'} );
    my $request_uri = $ENV{'REQUEST_URI'};
    if (
        @file_types
        && ! grep { $request_uri =~ m/$_/i } @file_types
    ) {
        $app->response_code('404');
        return $app->redirect($redirect);
    }

    my $host = (
            $ENV{'HTTPS'} && $ENV{'HTTPS'} eq 'on'
            ? 'https://' : 'http://'
        ) . $ENV{'HTTP_HOST'} . $ENV{'REQUEST_URI'};
    my $base = $blog->site_url;
    # Add the trailing slash, if needed.
    $base =~ s!(.*?)\/?$!$1\/!;

    my ($target) = ($host =~ /$base(.*)/);

    my $log = $app->model('cleansweep_log')->load({
        uri     => $target,
        blog_id => $blog->id,
    });

    unless ($log) {
        $log = CleanSweep::Log->new;
        $log->uri($target);
        $log->full_uri($ENV{'REQUEST_URI'});
        $log->blog_id($blog->id);
        $log->all_time_occur(0);
        $log->occur(0);
    }

    # 301 - Moved permanently
    # 302 - Found, but redirect may change
    # A mapping has been explicitly set for this resource, but the mapped URL
    # *does not* match the originating URL (which would cause an endless loop).
    if ($log->mapping && $log->mapping !~ /$target/) {
        $redirect = $log->mapping;
        $app->response_code("301");
    }
    # This resource was specifically set to Permanently Removed (410) or
    # Forbidden (403).
    elsif ($log->return_code) {
        $app->response_code($log->return_code);
        # $redirect already set to the 404 page.
    }
    # Try to guess the URL.
    elsif (
        $redirect = _guess_intended({
            app    => $app,
            target => $target,
            blog   => $blog,
            config => $config
        })
    ) {
        # We want to record that the URL was not found this one time, but a
        # redirect was created for future mappings.
        $log->increment();
        # A good guess was made about the URL. Save it.
        $log->mapping($redirect);
        $log->return_code('301');
        $log->save or die $log->errstr;
        $app->response_code("301");

        _track_referrer({ log_id => $log->id, });
    }
    # Give up and just redirect to the custom 404 page.
    elsif ($config->{'404url'}) {
        $log->increment();
        $log->save or die $log->errstr;
        # $redirect already set to the 404 page.
        $app->response_code("404");

        _track_referrer({ log_id => $log->id, });
    }
    else {
        $log->increment();
        $log->save or die $log->errstr;

        _track_referrer({ log_id => $log->id, });

        $redirect = $app->{cfg}->CGIPath . $app->{cfg}->SearchScript 
            . '?IncludeBlogs=' . $blog->id . '&keyword=' . $target;
    }

    # Finally, redirect the user to the selected page -- whatever it may be.
    $redirect .= '?target=' . $target
        if $config->{'append_request_url'};
    $app->redirect($redirect);
}

# Record where the visitor came from (the referrer) so that the MT admin can
# have an understanding of where the broken link came from.
sub _track_referrer {
    my ($arg_ref)    = @_;
    my $log_id       = $arg_ref->{log_id};
    my $referrer_uri = $ENV{'HTTP_REFERER'};

    # Give up if no referrer was supplied.
    return if !$referrer_uri;

    my $referrer = MT->model('cleansweep_referrer')->load({
        referrer_uri => $referrer_uri,
    });

    # This referrer was found already; just increment number of occurrences.
    if ( $referrer ) {
        my $count = $referrer->count || '1';
        $referrer->occur( $count++ );
    }
    else {
        $referrer = MT->model('cleansweep_referrer')->new();
        $referrer->log_id( $log_id );
        $referrer->referrer_uri( $referrer_uri );
        $referrer->occur( 1 );
    }

    $referrer->save or die $referrer->errstr;
}

# Try to guess the intended URL. The accessed URL is parsed to try to
# determine what the intended page might be.
sub _guess_intended {
    my ($arg_ref) = @_;
    my $app    = $arg_ref->{app};
    my $uri    = $arg_ref->{target};
    my $blog   = $arg_ref->{blog};
    my $config = $arg_ref->{config};
    my $entry;
    require MT::FileInfo;

    # Test 1: is the target a possible entry ID?
    if (my ($id) = ($uri =~ /\/(\d+)\.(\w+).*$/)) {
        $id =~ s/^0+//; 
        my $fi = MT::FileInfo->load({ entry_id => $id });
        return $fi->url
            if $fi;
    }

    # Test 2: is the target using underscore when it should be using hyphens?
    my $uri_tmp = $uri;
    $uri_tmp =~ s/_/-/g;
    if (my $fi = MT::FileInfo->load({ url => "/$uri_tmp" })) {
        if ( $fi->entry_id ) {
            $entry = $app->model('entry')->exist({
                id     =>$fi->entry_id,
                status => $app->model('entry')->RELEASE(), # Must be published
                class  => '*', # Entry or Page
            });
            return $fi->url if $entry;
        }
    }

    # Test 3: look for entry with same basename
    # The URI can contain the filename, or a path and the filename. Examples:
    # * my-awesome-entry.html
    # * 2011/10/01/my-awesome-entry.html
    # We want to get at the basename in either case.
    my ($path,$basename,$ext) = ($uri =~ /(.*\/)?([^\.]*)\.(\w+).*$/i);
    $basename =~ s/-/_/g;
    $entry = $app->model('entry')->load({
        basename => $basename,
        blog_id  => $blog->id,
        status   => $app->model('entry')->RELEASE(), # Must be published
        class    => '*', # Entry or Page
    });
    return $entry->permalink if $entry;

    # Test 3b: look for entries with the same basename in any child blogs.
    if ( $blog->class eq 'website') {
        my @child_blog_ids;
        my $iter = $app->model('blog')->load_iter({
            parent_id => $blog->id,
        });
        while ( my $child_blog = $iter->() ) {
            push @child_blog_ids, $child_blog->id;
        }
        if ( @child_blog_ids ) {
            $entry = $app->model('entry')->load({
                basename => $basename,
                blog_id  => \@child_blog_ids,
                status   => $app->model('entry')->RELEASE(), # Must be published
                class    => '*', # Entry or Page
            });
        }
        return $entry->permalink if $entry;
    }

    # Test 4: Look up the directory tree to see if something else can be served.
    # This option can be enabled/disabled because it may not be helpful,
    # depending upon site architecture.
    if ( $config->{traverse_url} ) {
        my $url = $blog->site_url . $uri;
        # Chop off the end of the URL so that the parent directory can be
        # checked. Clean Sweep will then redirect to that URL. If that URL
        # doesn't exist then they'll end up back here again and check for a
        # parent or be back at the site URL.
        # http://example.com/a/b/c/d.html
        # http://example.com/a/b/c/
        $url =~ s/^(.*\/).+/$1/
            if $url ne $blog->site_path;
        return $url;
    }

    return undef;
}

sub _finder {
    # $_ is the file
    my $dir = $File::Find::dir;
    my $name = $File::Find::name;
    if ( -f $name ) {
        # print STDERR 'file: ' . $name . "\n";
    }
}

sub widget_links {
    my $app = shift;
    my ( $tmpl, $param ) = @_;
    require CleanSweep::Log;

    my $args = {
        offset    => 0, 
        sort      => 'occur', 
        direction => 'descend', 
        limit     => 10,
    };

    my $terms = {};
    $terms->{blog_id} = $app->blog->id if $app->blog;

    my @links = CleanSweep::Log->load( $terms, $args );
    my @link_loop;
    my $count = 0;
    foreach my $l (@links) {
        my $row = {
            uri       => $l->uri,
            id        => $l->id,
            occur     => $l->occur,
            count     => $count,
            '__odd__' => ($count++ % 2 == 0),
        };

        my $uri_short = $l->uri;
        if (length($uri_short) > 30) {
            $uri_short =~ s/.*(.{30})$/$1/;
            $row->{uri_short} = $uri_short;
        }

        push @link_loop, $row;
    }

    $param->{html_head} .= '<link rel="stylesheet" href="' 
        . $app->static_path
        . 'support/plugins/cleansweep/styles/app.css" type="text/css" />';
    $param->{object_loop} = \@link_loop;
}

# The Dashboard widget should only display on the blog-level dashboard.
sub widget_condition {
    my ($page, $scope) = @_;
    return 1 if ( $scope !~ /system/ );
}

sub list_404 {
    my $app    = shift;
    my %param  = @_;
    my $q      = $app->can('query') ? $app->query : $app->param;
    my $plugin = MT->component('CleanSweep');
    my $author = $app->user;
    # my $list_pref = $app->list_pref('404');

    my $base = $app->blog->site_url;
    # Add the trailing slash, if needed.
    $base =~ s!(.*?)\/?$!$1\/!;

    my $date_format     = "%Y.%m.%d";
    my $datetime_format = "%Y-%m-%d %H:%M:%S";

    my $code = sub {
        my ($obj, $row) = @_;

        $row->{uri_long}    = encode_html($obj->uri);
        $row->{id}          = $obj->id;
        $row->{return_code} = $obj->return_code;
        $row->{map}         = $obj->mapping 
                                || "<em>" . $app->translate("None") . "</em>";
        # is_mapped is set to true/false based on the object's return_code.
        $row->{is_mapped}   = $obj->return_code;
        $row->{all_time}    = $obj->all_time_occur;
        $row->{count}       = $obj->occur;

        if ($obj->mapping) {
            $row->{return_code} = "301";
        }

        # If the URI is longer than will display on the listing screen, create
        # a "short" version that will fit.
        my $uri_short = $obj->uri;
        if (length($uri_short) > 50) {
            $uri_short =~ s/.*(.{50})$/$1/;
            $row->{uri_short} = $uri_short;
        }

        if ( my $ts = $obj->last_requested ) {
            $row->{created_on_formatted}
                = format_ts( 
                    $date_format, 
                    $ts, 
                    $app->blog, 
                    $app->user ? $app->user->preferred_language : undef 
                );
            $row->{created_on_time_formatted}
                = format_ts( 
                    $datetime_format, 
                    $ts, 
                    $app->blog, 
                    $app->user ? $app->user->preferred_language : undef 
                );
            $row->{created_on_relative}
                = relative_date( $ts, time, $app->blog );
        }
    };

    my %terms = (
        blog_id => $app->blog->id,
    );

    my %args = (
        sort      => 'occur',
        direction => 'descend',
    );

    my %params = (
        map_saved    => $q->param('map_saved') || '0',
        uri_reset    => $q->param('uri_reset') || '0',
        uri_delete   => $q->param('uri_delete') || '0',
        nav_404      => 1,
        list_noncron => 1,
    );

    $app->listing({
        type     => 'cleansweep_log',
        terms    => \%terms,
        args     => \%args,
        listing_screen => 1,
        code     => $code,
        template => $plugin->load_tmpl('list.tmpl'),
        params   => \%params,
    });
}

# The QuickFilter "Mapped URIs" option that filters the list view to see only
# those objects that have been mapped -- whether to another URI or a 410/403.
sub filter_mapped_uris {
    my ( $terms, $args ) = @_;
    $terms->{return_code} = { not_null => 1 };
}

# The QuickFilter "Recently Logged" option lists entries objects with the most
# recently logged first.
sub filter_recently_logged {
    my ( $terms, $args ) = @_;
    $args->{sort} = 'last_requested';
    $args->{direction} = 'descend';
}

# This QuickFilter shows 301 redirects
sub filter_301s {
    my ( $terms, $args ) = @_;
    $terms->{return_code} = '301';
    $args->{direction} = 'descend';
}

# This QuickFilter shows 410 redirects
sub filter_410s {
    my ( $terms, $args ) = @_;
    $terms->{return_code} = '410';
    $args->{direction} = 'descend';
}

# This QuickFilter shows 403 redirects
sub filter_403s {
    my ( $terms, $args ) = @_;
    $terms->{return_code} = '403';
    $args->{direction} = 'descend';
}

# This QuickFilter will show any 404s that haven't been mapped yet.
sub filter_umapped_uris {
    my ( $terms, $args ) = @_;
    $terms->{return_code} = \' IS NULL';
}

# Click the "reset" link on the listing screen.
sub itemset_reset_404s {
    my ($app) = @_;
    $app->validate_magic or return;

    my @links = $app->param('id');

    require CleanSweep::Log;
    LINK: for my $link (@links) {
        my $link = CleanSweep::Log->load($link)
          or next LINK;
        $link->reset();
    }

    my $cgi = $app->{cfg}->CGIPath . $app->{cfg}->AdminScript;
    $app->redirect(
        "$cgi?__mode=list&_type=cleansweep_log&blog_id=" . $app->blog->id
        . "&uri_reset=1"
    );
}

sub itemset_delete_404s {
    my ($app) = @_;
    $app->validate_magic or return;

    my @links = $app->param('id');

    require CleanSweep::Log;
    LINK: for my $link (@links) {
        my $link = CleanSweep::Log->load($link)
          or next LINK;

        # Remove any referrers for this 404.
        my @referrers = MT->model('cleansweep_referrer')->load({
            log_id => $link->id,
        });
        foreach my $referrer (@referrers) {
            $referrer->remove();
        }

        # Remove this 404.
        $link->remove();
    }

    my $cgi = $app->{cfg}->CGIPath . $app->{cfg}->AdminScript;
    $app->redirect(
        "$cgi?__mode=list&_type=cleansweep_log&blog_id=" . $app->blog->id
        . "&uri_delete=1"
    );
}

sub save_map {
    my $app = shift;
    my $q   = $app->can('query') ? $app->query : $app->param;
    my $param;

    require CleanSweep::Log;
    my $link = CleanSweep::Log->load($q->param('id'));

    unless ($link) {
        $link = CleanSweep::Log->new; # this can never happen
    }

    $link->map('');

    $link->return_code($q->param('return_code'));

    if ($q->param('return_code') eq "301") {
        $link->map($q->param('destination'));
    }
    $link->save or die $app->error( $link->errstr );

    $app->redirect( $q->param('return_to') . '&map_saved=1');
}

# Clicking the "map" link causes a popup to appear with the options for how
# a given URL can be handled.
sub map {
    my $app     = shift;
    my ($param) = @_;
    my $q       = $app->can('query') ? $app->query : $app->param;
    my $plugin  = MT->component('CleanSweep');

    $param ||= {};

    my $blog = $app->blog;

    my $base = $blog->site_url;
    # Add the trailing slash, if needed.
    $base =~ s!(.*?)\/?$!$1\/!;

    require CleanSweep::Log;
    my $link = CleanSweep::Log->load($q->param('id'));

    $param->{base_url}    = $base;
    $param->{uri}         = $link->uri;
    $param->{id}          = $link->id;
    $param->{blog_id}     = $app->blog->id;
    $param->{map}         = $link->mapping;
    $param->{return_code} = $link->return_code || "301";
    $param->{is_mapped}   = ($link->return_code || $link->mapping);
    $param->{return_to}   = $q->param('return_to');
    
    my @referrers = MT->model('cleansweep_referrer')->load({ log_id => $link->id });
    $param->{referrers} = \@referrers;

    return $plugin->load_tmpl( 'dialog/map.tmpl', $param);
}

sub rules {
    my $app    = shift;
    my $q      = $app->can('query') ? $app->query : $app->param;
    my $plugin = $app->component('CleanSweep');
    my $blog   = $app->blog;
    my $config = $plugin->get_config_hash('blog:'.$blog->id);
    my $base   = $blog->site_url;
    my $param ||= {};


    my $args = {
        sort      => 'uri',
        direction => 'ascend'
    };

    require CleanSweep::Log;
    my @links = CleanSweep::Log->load( { blog_id => $app->blog->id }, $args );
    my @link_loop;
    foreach my $l (@links) {
        my $row = {
            id          => $l->id,
            uri         => $l->uri,
            map         => $l->mapping,
            code        => $l->return_code || "301",
            has_mapping => $l->return_code || $l->mapping, 
        };

        if ( $l->return_code && $l->return_code == 410 ) {
            $row->{redir_code} = "G"; 
        }
        elsif ( $l->return_code && $l->return_code == 403 ) {
            $row->{redir_code} = "F";
        }
        elsif ( $l->mapping ) {
            $row->{redir_code} = "R=301";
        }

        push @link_loop, $row;
    }
    $param->{object_loop} = \@link_loop;

    $param->{base_url}  = $base;
    $param->{blog_id}   = $app->blog->id;
    $param->{webserver} = $config->{'webserver'};

    return $plugin->load_tmpl( 'dialog/rules.tmpl', $param);
}

1;
