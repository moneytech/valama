/*
 * src/project/project_templates.vala
 * Copyright (C) 2012, 2013, Valama development team
 *
 * Valama is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Valama is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

using GLib;
using Xml;
using Gee;

public class ProjectTemplate {
    public Gdk.Pixbuf? icon = null;
    public ArrayList<TemplateAuthor?> authors;
    public ArrayList<TemplateValaVersion?> versions;
    public string version = "0";
    public string name;
    public string path;
    public string description;
    public string? long_description = null;

    public string[]? packages { get; private set; default = null; }
    public string[]? unmet_deps { get; private set; default = null; }
    public TreeSet<string>? s_files  { get; private set; default = null; }
    public string[]? b_files { get; private set; default = null; }

    public ProjectTemplate() {
        authors = new ArrayList<TemplateAuthor?>();
        versions = new ArrayList<TemplateValaVersion?>();
    }

    /**
     * Initialize package and file list and get unmet dependencies.
     *
     * @param available_packages List of all available_packages on system.
     */
    public void init (string[] available_packages) throws LoadingError
                                                   requires (path != null) {
        var vlp_file = Path.build_path (Path.DIR_SEPARATOR_S, path, "template.vlp");
        var vproject = new ValamaProject (vlp_file, null, false);

        packages = vproject.packages.to_array();

        s_files = new TreeSet<string>();
        vproject.generate_file_list (vproject.source_dirs.to_array(),
                                     vproject.source_files.to_array(),
                                     (filename) => {
            if (!(filename.has_suffix (".vala") || filename.has_suffix (".vapi")))
                return;
            s_files.add (vproject.get_relative_path (filename));
        });

        switch (vproject.buildsystem) {
            default:
                debug_msg (_("Buildsystem '%s' currently not supported by template selector.\n"),
                           vproject.buildsystem);
                break;
        }

        var unmet = new string[0];
        foreach (var depend in vproject.packages)
            if (!(depend in available_packages))
                unmet += depend;
        foreach (ValamaProject.PkgChoice choice in vproject.package_choices) {
            foreach (var choice_pkg in choice.packages)
                if (choice_pkg in available_packages)
                    continue;
            var unmet_string = "";
            foreach (var choice_pkg in choice.packages)
                unmet_string += choice_pkg + "/";
            unmet += unmet_string;
        }
        unmet_deps = unmet;
    }
}

public class TemplateAuthor {
    public string? name = null;
    public string? mail = null;
    public string? date = null;
    public string? comment = null;
}

public class TemplateValaVersion {
    public VersionRelation rel = VersionRelation.ONLY;
    public string? version = null;
}

public enum VersionRelation {
    SINCE,  // >=
    UNTIL,  // <=
    ONLY,   // ==
    EXCLUDE // !=
}

/**
 * Current compatible version of template file.
 */
public const string TEMPLATE_VERSION_MIN = "0.1";

/**
 * Load all available {@link ProjectTemplate} information.
 *
 * @return Return list of all found templates.
 */
public ProjectTemplate[] load_templates() {
    FileInfo file_info;
    ProjectTemplate[] ret = new ProjectTemplate[0];

    var locales = new ArrayList<string>();
    foreach (var lang in Intl.get_language_names())
        locales.add (lang);

    string dirpath;
    if (Args.templatesdir == null)
        dirpath = Path.build_path (Path.DIR_SEPARATOR_S,
                                   Config.PACKAGE_DATA_DIR,
                                   "templates");
    else
        dirpath = Args.templatesdir;
    var directory = File.new_for_path (dirpath);
    try {
        var enumerator = directory.enumerate_children (FileAttribute.STANDARD_NAME, 0);

        while ((file_info = enumerator.next_file()) != null) {
            var infof = File.new_for_path (Path.build_path (Path.DIR_SEPARATOR_S,
                                                            dirpath,
                                                            file_info.get_name(),
                                                            file_info.get_name() + ".info"));
            if (!infof.query_exists())
                continue;
            var filename = infof.get_path();

            var new_template = new ProjectTemplate();
            new_template.name = file_info.get_name();
            new_template.path = Path.build_path (Path.DIR_SEPARATOR_S,
                                                 dirpath,
                                                 new_template.name,
                                                 "template");
            //TODO: Ignore case.
            foreach (var filetype in new string[] {"png",
                                                   "jpg",
                                                   "jpeg",
                                                   "svg"}) {
                var icon_path = Path.build_path (Path.DIR_SEPARATOR_S,
                                                 dirpath,
                                                 new_template.name,
                                                 new_template.name + "." + filetype);
                if (FileUtils.test (icon_path, FileTest.EXISTS)) {
                    try {
                        new_template.icon = new Gdk.Pixbuf.from_file (icon_path);
                        break;
                    } catch (GLib.Error e) {
                        warning_msg (_("Could not load template image: %s\n"), e.message);
                    }
                }
            }

            Xml.Doc* doc = Xml.Parser.parse_file (filename);
            Xml.Node* root_node;

            try {
                if (doc == null) {
                    delete doc;
                    throw new LoadingError.FILE_IS_GARBAGE (_("Cannot parse file."));
                }

                root_node = doc->get_root_element();
                if (root_node == null) {
                    delete doc;
                    throw new LoadingError.FILE_IS_EMPTY (_("File does not contain enough information"));
                }

                if (root_node->has_prop ("version") != null)
                    new_template.version = root_node->get_prop ("version");
                if (comp_proj_version (new_template.version, TEMPLATE_VERSION_MIN) < 0) {
                    var errstr = _("Template file '%s' too old: %s < %s").printf (new_template.path,
                                                                                  new_template.version,
                                                                                  TEMPLATE_VERSION_MIN);
                    if (!Args.forceold) {
                        delete doc;
                        throw new LoadingError.FILE_IS_OLD (errstr);
                    } else
                        warning_msg (_("Ignore template file loading error: %s\n"), errstr);
                }
            } catch (LoadingError e) {
                warning_msg (_("Could not load template '%s': %s\n"), filename, e.message);
                continue;
            }

            for (Xml.Node* i = root_node->children; i != null; i = i->next) {
                if (i->type != ElementType.ELEMENT_NODE)
                    continue;
                switch (i->name) {
                    case "vala-version":
                        var version = new TemplateValaVersion();
                        version.version = i->get_content();
                        if (i->has_prop ("rel") != null)
                            switch (i->get_prop ("rel")) {
                                case "since":
                                    version.rel = VersionRelation.SINCE;
                                    break;
                                case "until":
                                    version.rel = VersionRelation.UNTIL;
                                    break;
                                case "only":
                                    version.rel = VersionRelation.ONLY;
                                    break;
                                case "exclude":
                                    version.rel = VersionRelation.EXCLUDE;
                                    break;
                                default:
                                    warning_msg (_("Unknown property for 'vala-version' line %hu: %s\n"), i->line, i->get_prop ("rel"));
                                    break;
                            }
                        new_template.versions.add (version);
                        break;
                    case "author":
                        var author = new TemplateAuthor();
                        for (Xml.Node* p = i->children; p != null; p = p->next) {
                            if (p->type != ElementType.ELEMENT_NODE)
                                continue;
                            switch (p->name) {
                                case "name":
                                    author.name = p->get_content();
                                    break;
                                case "mail":
                                    author.mail = p->get_content();
                                    break;
                                case "date":
                                    author.date = p->get_content();
                                    break;
                                case "comment":
                                    author.comment = get_lang_content (p, locales);
                                    break;
                                default:
                                    warning_msg (_("Unknown configuration file value line %hu: %s\n"), p->line, p->name);
                                    break;
                            }
                        }
                        new_template.authors.add (author);
                        break;
                    case "name":
                        new_template.name = get_lang_content (i, locales);
                        if (new_template == null) {
                            warning_msg (_("Template has no name: line %hu"), i->line);
                            new_template.name = "";
                        }
                        break;
                    case "description":
                        new_template.description = get_lang_content (i, locales);
                        if (new_template.description == null) {
                            debug_msg (_("Template has no description: line %hu"), i->line);
                            new_template.description = "";
                        }
                        break;
                    case "long-description":
                        new_template.long_description = get_lang_content (i, locales);
                        break;
                    default:
                        warning_msg (_("Unknown configuration file value line %hu: %s\n"), i->line, i->name);
                        break;
                }
            }
            delete doc;
            ret += new_template;
        }
    } catch (GLib.Error e) {
        errmsg (_("Could not get template directory files: %s\n"), e.message);
    }

    return ret;
}


/**
 * Load item from list and select only valid locales (from priority list).
 *
 * @param node {@link Xml.Node} pointer to start (plain) lookup.
 * @param locales List of locales ordered by priority.
 * @return Return highest priority item or null if no matching locale found.
 */
private string? get_lang_content (Xml.Node* node, ArrayList<string?> locales) {
    int locid = locales.size;
    string? desc_start = null;
    string? desc = null;
    for (Xml.Node* p = node->children; p != null; p = p->next) {
        if (p->type != ElementType.ELEMENT_NODE)
            continue;
        if (desc_start == null)
            desc_start = p->get_content();
        var tmpid = locales.index_of (p->name);
        if (tmpid >= 0 && tmpid < locid) {
            locid = tmpid;
            desc = p->get_content();
            if (tmpid == 0)
                break;
        }
    }
    if (desc != null)
        return desc;
    else if (desc_start != null)
        return desc_start;
    return null;
}

// vim: set ai ts=4 sts=4 et sw=4