# This program is distributed under the terms of the
# GNU General Public License, version 2.
#
# $Id: CMS.pm 1534 2009-05-24 23:52:58Z breese $

package Assetylene::CMS;

use strict;
use MT 4;
use Assetylene::L10N;
use MT::Util qw( encode_html );

my $post_process_upload;
sub init_app {
    # MT 5.0 or greater
    return unless MT->version_number >= 5.0;

    # Override the MT::CMS::Asset:_post_process method to call asset
    # save_filter, pre_save, and post_save callbacks to process custom
    # fields when asset is saved.
    require MT::CMS::Asset;
    no warnings 'redefine';
    unless ($post_process_upload) {
        $post_process_upload = \&MT::CMS::Asset::_process_post_upload;
        *MT::CMS::Asset::_process_post_upload = \&_process_post_upload;
    }
}

sub asset_options_image {
    my ($cb, $app, $param, $tmpl) = @_;

    # Assertions:
    # 'asset_id' template parameter must be present.
    my $asset_id = $param->{asset_id} or return;

    # Asset object must be loadable
    my $asset = MT::Asset->load( $asset_id ) or return;

    # The 'image_alignment' MT template node must be in
    # the template we're working with to add our field above it.
    my $el = $tmpl->getElementById('image_alignment')
        or return;

    my $blog = $app->blog or return;
    my $plugin = MT->component("Assetylene");
    my $scope = "blog:".$blog->id;
    my $insert_tmpl = $app->model('template')->load({
                                                name => 'Asset Insertion',
                                                type => 'custom',
                                                blog_id => [ $blog->id, 0 ]
                                               }) ||
                      $app->model('template')->load({
                                                identifier => 'asset_insertion',
                                                type => 'custom',
                                                blog_id => [ $blog->id, 0 ]
                                               });
    my $opt;
    # Force the tokens of the template to be reprocessed now that
    # we've manipulated it:
    $tmpl->rescan();
}

sub asset_insert {
    my ($cb, $app, $param, $tmpl) = @_;

    my $blog_id = $app->param('blog_id');
    use MT::Blog;
    my $blog = MT::Blog->load($blog_id) or die;
    my $plugin = MT->component("Assetylene");
    my $scope = "blog:".$blog_id;

    # Do not change markup if selecting asset for custom field
    return 1 if $param->{edit_field} =~ /customfield/;

    # Assertions:
    # Load the user-defined "Asset Insertion" template module.
    # Currently, this template must be named in English. Look both
    # at the blog and system level for this template.
    my $insert_tmpl = $app->model('template')->load({
                                                name => 'Asset Insertion',
                                                type => 'custom',
                                                blog_id => [ $blog->id, 0 ]
                                               }) ||
                      $app->model('template')->load({
                                                identifier => 'asset_insertion',
                                                type => 'custom',
                                                blog_id => [ $blog->id, 0 ]
                                               });
    return unless $insert_tmpl;

    my $asset = $tmpl->context->stash('asset');

    # Collect all the elements of the MT generated asset markup
    # so they can be manipulated indepdendently by the user-defined
    # template:
    my $html = $param->{upload_html};
    my ($img_tag) = $html =~ /(<img\b[^>]+?>)/s;
    my ($a_tag) = $html =~ /(<a\b[^>]+?>)/s;
    my ($form_tag) = $html =~ /(<form[^>]+?>)/s;

    $param->{enclose} = 1 if $form_tag;
    $param->{include} = 1 if $app->param('include');
    $param->{thumb} = 1 if $app->param('thumb');
    ($param->{align}) = $app->param('align') =~ m/(\w+)/;
    $param->{caption} = $app->param('insert_caption') ? $app->param('caption') : '';
    $param->{popup} = 1 if $app->param('popup');

    $param->{label} = $asset->label;
    $param->{description} = $asset->description;
    $param->{asset_id} = $asset->id;

    $param->{a_tag} = $a_tag;
    ($param->{a_href}) = $a_tag =~ /\bhref="(.+?)"/s;
    ($param->{a_onclick}) = $a_tag =~ /\bonclick="(.+?)"/s;

    $param->{form_tag} = $form_tag;
    ($param->{form_style}) = $form_tag =~ /\bstyle="([^\"]+)"/s;
    ($param->{form_class}) = $form_tag =~ /\bclass="([^\"]+)"/s;

    $param->{img_tag} = $img_tag;
    ($param->{img_height}) = $img_tag =~ /\bheight="(\d+)"/;
    ($param->{img_width}) = $img_tag =~ /\bwidth="(\d+)"/;
    ($param->{img_src}) = $img_tag =~ /\bsrc="([^\"]+)"/s;
    ($param->{img_style}) = $img_tag =~ /\bstyle="([^\"]+)"/s;
    ($param->{img_class}) = $img_tag =~ /\bclass="([^\"]+)"/s;
    ($param->{img_alt}) = $img_tag =~ /\balt="([^\"]+)"/s;

    $insert_tmpl->param( $param );

    my $ctx = $insert_tmpl->context;
    $ctx->stash('blog', $blog);
    $ctx->stash('blog_id', $blog->id);
    $ctx->stash('local_blog_id', $blog->id);
    $ctx->stash('asset', $asset);

    # Process the user-defined template:
    my $new_html = $insert_tmpl->output;

    unless (defined($new_html)) {
        # Template build error: die, so this gets logged (we're in a
        # callback, so it won't be surfaced to the user unfortunately)
        die "Error from Asset Insertion module: " . $insert_tmpl->errstr;
    }
    my $ua = $ENV{'HTTP_USER_AGENT'};
    if ($ua =~ /MSIE/) {
        $new_html =~ s/<!--[\s\S]*?-->//g;
    }
    $new_html =~ s/\s*\n+/\n/g;
    # Replace the MT generated asset markup with the user-defined
    # markup:
    $param->{upload_html} = $new_html;

}

sub asset_options {
    my ($cb, $app, $param, $tmpl) = @_;

    my $blog = $app->blog;
    my $blog_id = $blog->id;

    # Assertions:
    # Need MT 5.0 or greater
    return unless MT->version_number >= 5.0;

    # Commercial.pack addon (custom fields) must be present
    return unless MT->component('Commercial');

    # 'asset_id' template parameter must be present.
    my $asset_id = $param->{asset_id} or return;

    # Asset object must be loadable
    my $asset = MT::Asset->load( $asset_id ) or return;


    # Insert asset/image/audio/video custom fields


    # The 'tags' MT template node must be in the template
    # we're working with to add custom fields below it.
    my $el = $tmpl->getElementById('tags')
        or return;

    # createElement() does not pass 'attribute_list' parameter
    # (required for multiple instances of the same attribute
    # such as 'regex_replace'), so we have to directly create
    # an MT::Template::Node element.
    my $custom_fields = MT::Template::Node->new(
        tag => 'app:fields',
        attributes => {
            blog_id => $blog_id,
            object_type => $asset->class, 
            object_id => $asset_id,
            regex_replace => 1,
        },
        attribute_list => [
            [ regex_replace => ['/class="text"/g','class="text full"'] ],
            [ regex_replace => ['/class="text high"/g','class="text full low"'] ],
        ],
    );

    # Insert custom fields below the 'tags' field:
    $tmpl->insertAfter($custom_fields, $el);
    # Force the tokens of the template to be reprocessed now that
    # we've manipulated it:
    $tmpl->rescan();


    # Insert jQuery needed for date/time custom fields

    
    # The 'mt:Include' MT template tag including 'dialog/footer.tmpl' must be
    # in the template we're working with to add setvarblock tag above it.
    my $el2 = ${$tmpl->getElementsByName('dialog/footer.tmpl')}[0]
        or return;

    my $setvarblock_jq = $tmpl->createElement('setvarblock', {
        name => 'jq_js_include',
        append => 1,
    });

    # Contents of the setvarblock tag:
    $setvarblock_jq->innerHTML(<<HTML2);
    jQuery('input.text-date').datepicker({
        dateFormat: 'yy-mm-dd',
        dayNamesMin: [<__trans phrase="_LOCALE_CALENDAR_HEADER_">],
        monthNames: ['- 01','- 02','- 03','- 04','- 05','- 06','- 07','- 08','- 09','- 10','- 11','- 12'],
        showMonthAfterYear: true,
        prevText: '&lt;',
        nextText: '&gt;'
    });
HTML2

    # Insert setvarblock above the 'mt:include' tag:
    $tmpl->insertBefore($setvarblock_jq, $el2);
    # Force the tokens of the template to be reprocessed now that
    # we've manipulated it:
    $tmpl->rescan();


    # Add <link> tag to Commercial.pack .css file for custom fields styles


    # The 'mt:Include' MT template tag including 'dialog/header.tmpl' must be
    # in the template we're working with to add setvarblock tag above it.
    my $el3 = ${$tmpl->getElementsByName('dialog/header.tmpl')}[0]
        or return;

    my $setvarblock_css = $tmpl->createElement('setvarblock', {
        name => 'html_head',
        append => 1,
    });

    # Contents of the setvarblock tag:
    $setvarblock_css->innerHTML(<<'HTML3');
<link rel="stylesheet" href="<mt:var name="static_uri">addons/Commercial.pack/styles-customfields.css" type="text/css" media="screen" title="CustomFields Stylesheet" charset="utf-8" />
HTML3

    # Insert setvarblock above the 'mt:include' tag:
    $tmpl->insertBefore($setvarblock_css, $el3);
    # Force the tokens of the template to be reprocessed now that
    # we've manipulated it:
    $tmpl->rescan();
}

sub asset_options_source {
    my ($cb, $app, $src) = @_;

    # Assertions:
    # Need MT 5.0 or greater
    return unless MT->version_number >= 5.0;

    # Commercial.pack addon (custom fields) must be present
    return unless MT->component('Commercial');

    my $magic_token = '<input type="hidden" name="magic_token" value="<mt:var name="magic_token">" />';
    my $asset_type = '  <input type="hidden" name="asset_type" value="<mt:Asset id="$asset_id"><mt:AssetProperty property="class" escape="html"></mt:Asset>" />';
    
    $$src =~ s/($magic_token)/$1\n$asset_type/;
}

sub _process_post_upload {
    my $app   = shift;
    my %param = $app->param_hash;
    my $asset;
    require MT::Asset;
    $param{id} && ( $asset = MT::Asset->load( $param{id} ) )
        or return $app->errtrans("Invalid request.");

    my $mt_version = MT->version_number;
    my ( $need_perm_check, $perm_check );

    if ( $mt_version < 5.1 ) {        # MT 5.0x
        if ( $mt_version >= 5.07 ) {
            $need_perm_check = 1;
        }
    } elsif ( $mt_version < 5.2 ) {   # MT 5.1x
        if ( $mt_version >= 5.13 ) {
            $need_perm_check = 1;
        }
    } else {                          # MT 5.2x
        $need_perm_check = 1;
    }

    if ($need_perm_check) {
        $perm_check =
            ( $app->can('edit_assets') || $asset->created_by == $app->user->id );
    }

    unless ( $need_perm_check && !$perm_check ) {
        my $original = $asset->clone; # For post_save callback
        $asset->label( $param{label} )             if $param{label};
        $asset->description( $param{description} ) if $param{description};
        if ( $param{tags} ) {
            require MT::Tag;
            my $tag_delim = chr( $app->user->entry_prefs->{tag_delim} );
            my @tags = MT::Tag->split( $tag_delim, $param{tags} );
            $asset->set_tags(@tags);
        }

        # Run save_filter callbacks prior to saving asset
        # Custom fields has callback here to validate and
        # pre-process custom fields before saving
        my $filter_result = $app->run_callbacks( 'cms_save_filter.asset', $app );
        return $app->error($app->errstr) unless $filter_result;

        # Added for completeness - no known custom fields callbacks
        $app->run_callbacks( 'cms_pre_save.asset', $app, $asset, $original );

        $asset->save();

        # Run post_save callbacks to save custom fields
        $app->run_callbacks( 'cms_post_save.asset', $app, $asset, $original );
    }

    $asset->on_upload( \%param );
    require MT::CMS::Asset;
    return MT::CMS::Asset::asset_insert_text( $app, \%param );
}

sub is_user_can {
    my ( $blog, $user, $permission ) = @_;
    $permission = 'can_' . $permission;
    my $perm = $user->is_superuser;
    unless ( $perm ) {
        if ( $blog ) {
            my $admin = 'can_administer_blog';
            $perm = $user->permissions( $blog->id )->$admin;
            $perm = $user->permissions( $blog->id )->$permission unless $perm;
        } else {
            $perm = $user->permissions()->$permission;
        }
    }
    return $perm;
}

sub doLog {
    my ($msg) = @_; 
    return unless defined($msg);
    require MT::Log;
    my $log = MT::Log->new;
    $log->message($msg) ;
    $log->save or die $log->errstr;
}

1;
