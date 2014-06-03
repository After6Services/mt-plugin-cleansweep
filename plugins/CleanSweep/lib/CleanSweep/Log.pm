#!/usr/bin/perl -w
#
# This software is licensed under the Gnu Public License, or GPL v2.
# 
# Copyright 2007, Six Apart, Ltd.

package CleanSweep::Log;

use strict;
use warnings;

use MT::Object;
use base qw( MT::Object );

__PACKAGE__->install_properties({
    column_defs => {
        id             => 'integer not null auto_increment', 
        blog_id        => 'integer not null', 
        uri            => 'string(255) not null',
        full_uri       => 'string(255) not null',
        occur          => 'integer not null',
        all_time_occur => 'integer not null',
        return_code    => 'string(5)',
        mapping        => 'string(255)',
        last_requested => 'datetime',
    },
    indexes => {
        blog_id    => 1,
        created_on => 1,
        uri        => 1,
    },
    audit       => 1,
    datasource  => 'cs_log',
    primary_key => 'id',
});

sub class_label {
    MT->translate("Logged 404");
}

sub class_label_plural {
    MT->translate("Logged 404s");
}

sub increment {
    my $obj = shift;
    if (!$obj->all_time_occur) {
        $obj->occur(0);
        $obj->all_time_occur(0);
    } 
    $obj->occur( $obj->occur + 1 );
    $obj->all_time_occur( $obj->all_time_occur + 1 );

    my @ts = MT::Util::offset_time_list(time, $obj->blog_id);
    my $ts = sprintf '%04d%02d%02d%02d%02d%02d', $ts[5]+1900, $ts[4]+1, @ts[3,2,1,0];
    $obj->last_requested($ts);
}

sub reset {
    my $obj = shift;
    $obj->occur(0);
    $obj->save;

    # Reset any referrers for this 404, also.
    my @referrers = MT->model('cleansweep_referrer')->load({
        log_id => $obj->id,
    });
    foreach my $referrer (@referrers) {
        $referrer->occur(0);
    }
}

sub map {
    my $obj = shift;
    my ($dest) = @_;
    $obj->mapping($dest);
    $obj->save;
}

# Properties for the Listing Framework in MT 5.1+.
sub list_properties {
    return {
        id => {
            auto    => 1,
            label   => 'ID',
            display => 'none',
        },
        # blog_id => {
        #     auto => 1,
        #     label => 'Blog',
        # },
        actions => {
            label   => 'Actions',
            order   => 50,
            display => 'force',
            html    => sub {
                my ($prop, $obj, $app, $options) = @_;

                return '<a href="javascript:void(0)" onclick="jQuery.fn.mtDialog.open(\''
                        . $app->app_uri . '?__mode=map_404&id=' . $obj->id
                        . '&blog_id=' . $obj->blog_id
                        . '&return_to=\' + encodeURIComponent(document.URL))">Map</a> '
                    . '<a href="'
                        . $app->app_uri . '?__mode=itemset_reset_404s&id='
                        . $obj->id . '&blog_id=' . $obj->blog_id
                        . '&magic_token=' . $app->current_magic . '">Reset</a>';
            },
        },
        uri => {
            base    => '__virtual.string',
            col     => 'uri',
            label   => 'URI',
            display => 'force',
            order   => 100,
            sub_fields => [
                {
                    class   => 'mapping',
                    label   => 'Mapping',
                    display => 'default',
                },
            ],
            html => sub {
                my ( $prop, $obj, $app, $opts ) = @_;

                my $source_url    = $obj->uri;
                my $mapped_to_url = '';

                if ( $obj->mapping ) {
                    $mapped_to_url = '<div class="mapping" style="color: #999;">'
                        . 'Mapped to: <span class="mapped_to_url">'
                        . $obj->mapping . '</span></div>';
                }

                return qq{
                    <div class="source_url">$source_url</div>
                    $mapped_to_url
                };
            },
        },
        last_requested => {
            base    => '__virtual.date',
            col     => 'last_requested',
            label   => 'Last Request',
            display => 'default',
            order   => 200,
        },
        occur => {
            base    => '__virtual.integer',
            col     => 'occur',
            label   => 'Occurrences',
            display => 'default',
            order   => 300,
        },
        return_code => {
            base    => '__virtual.integer',
            col     => 'return_code',
            label   => 'Return Code',
            display => 'default',
            order   => 400,
        },
        # mapping => {
        #     base    => '__virtual.string',
        #     col     => 'mapping',
        #     label   => 'Mapping',
        #     display => 'default',
        #     order   => 500,
        # },
    };
}

1;
