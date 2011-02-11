package Assetylene::Plugin;

use strict;
use MT 4.2;

sub xfm_src {
	my ($cb, $app, $tmpl) = @_;
    my $old = <<'HTML';
            <select name="site_path" id="site_path" onchange="setExtraPath(this)">
                <option value="1">&#60;<__trans phrase="Site Root">&#62;</option>
            <mt:if name="enable_archive_paths">
                <option value="0"<mt:if name="archive_path"> selected="selected"</mt:if>>&#60;<__trans phrase="Archive Root">&#62;</option>
            </mt:if>
            <mt:if name="extra_paths">
                <mt:loop name="extra_paths">
                <option value="<mt:if name="enable_archive_paths">0<mt:else>1</mt:if>" middle_path="<mt:var name="path" escape="html">"<mt:if name="selected"> selected="selected"</mt:if>><mt:var name="label" escape="html"></option>
                </mt:loop>
            </mt:if>
            </select>
            / <input type="text" name="extra_path" id="extra_path" class="extra-path" value="<mt:var name="extra_path" escape="html">" />
            &nbsp;<a href="javascript:void(0);" mt:command="open-folder-selector"><__trans phrase="Choose Folder"></a>
HTML
    $old = quotemeta($old);
    my $new = <<"HTML";
            <input type="hidden" name="site_path" value="1" />
            <__trans phrase="Site Root">&#62;<input type="text" name="extra_path" id="extra_path" class="extra-path" readonly="readonly" value="<mt:var name="extra_path" escape="html">" />
HTML
    $$tmpl =~ s!$old!$new!;

    $old = <<'HTML';
        <mtapp:setting
            id="site_path"
            label_class="top-label"
            label="<__trans phrase="Upload Destination">"
            hint="<$mt:var name="upload_hint"$>"
            show_hint="1">
HTML
    $old = quotemeta($old);
    $new = <<"HTML";
        <mtapp:setting
            id="site_path"
            label_class="top-label"
            label="<__trans phrase="Upload Destination">"
            show_hint="0">
HTML
    $$tmpl =~ s!$old!$new!;




    1;
}

1;