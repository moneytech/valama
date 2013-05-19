/*
 * guanako/guanako_frankenstein.vala
 * Copyright (C) 2013, Valama development team
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
using Vala;

namespace Guanako {
    public class FrankenStein {
        public FrankenStein() {
            var pid = ((int)Posix.getpid()).to_string();
            dbus_name = "app.valama.frankenstein" + pid;
            dbus_path = "/app/valama/frankenstein";
            build_frankenstein_mainblock();
            owner_id = Bus.own_name (BusType.SESSION, dbus_name, BusNameOwnerFlags.NONE,
                  on_bus_aquired,
                  () => {},
                  () => stderr.printf (_("Could not acquire name.\n")));
        }
        string dbus_name;
        string dbus_path;
        uint owner_id;

        ~FrankenStein() {
            Bus.unown_name (owner_id);
        }

        void on_bus_aquired (DBusConnection conn) {
            try {
                conn.register_object (dbus_path, new FrankenDBUS (this));
            } catch (IOError e) {
                stderr.printf (_("Could not register service.\n"));
            }
        }

        [DBus (name = "app.valama.frankenstein")]
        class FrankenDBUS : Object {
            public FrankenDBUS (FrankenStein parent) {
                this.parent = parent;
            }
            FrankenStein parent;
            public void timer_finished (int timer_id, double time) {
                parent.timer_finished (parent.frankentimers[timer_id], timer_id, time);
            }
            public void stop_reached (int stop_id) {
                parent.stop_reached (parent.frankenstops[stop_id], stop_id);
            }
        }

        public class FrankenTimer {
            public FrankenTimer(SourceFile file, int start_line, int end_line, bool active) {
                this.file = file;
                this.start_line = start_line;
                this.end_line = end_line;
                this.active = active;
            }
            public SourceFile file;
            public int start_line;
            public int end_line;
            public bool active;
        }

        public class FrankenStop {
            public FrankenStop(SourceFile file, int line, bool active) {
                this.file = file;
                this.line = line;
                this.active = active;
            }
            public SourceFile file;
            public int line;
            public bool active;
        }

        public Gee.ArrayList<FrankenTimer?> frankentimers = new Gee.ArrayList<FrankenTimer?>();
        public Gee.ArrayList<FrankenStop?> frankenstops = new Gee.ArrayList<FrankenStop?>();
        public signal void timer_finished (FrankenTimer timer, int timer_id, double time);
        public signal void stop_reached (FrankenStop stop, int stop_id);

        public string frankensteinify_sourcefile (SourceFile file) {
            //FIXME: Don't read entire file into memory.
            string[] lines = file.content.split ("\n");
            int cnt = 0;
            foreach (FrankenTimer ftime in frankentimers) {
                lines[ftime.start_line - 1] = @"var frankentimer_$cnt = new GLib.Timer();\n"
                                                + @"frankentimer_$cnt.start();\n"
                                                + lines[ftime.start_line - 1];
                lines[ftime.end_line - 1] = @"frankentimer_callback ($cnt, frankentimer_$cnt.elapsed());\n"
                                            + lines[ftime.end_line - 1];
                cnt++;
            }
            cnt = 0;
            foreach (FrankenStop fstop in frankenstops) {
                lines[fstop.line - 1] = @"frankenstop_callback($cnt);\n" + lines[fstop.line - 1];
                cnt++;
            }
            StringBuilder ret = new StringBuilder();
            foreach (string line in lines)
                ret.append (line + "\n");
            return ret.str;
        }

        public string frankenstein_mainblock { public get; private set; default = "";}

        private void build_frankenstein_mainblock () {
            frankenstein_mainblock = """
[DBus (name = "app.valama.frankenstein")]
interface FrankenDBUS : Object {
    public abstract void timer_finished (int timer_id, double time) throws IOError;
    public abstract void stop_reached (int stop_id) throws IOError;
}

static FrankenDBUS frankenstein_client = null;
static void frankentimer_callback (int timer_id, double time) {
    if (frankenstein_client == null) {
        try {
            frankenstein_client = Bus.get_proxy_sync (BusType.SESSION,
                                                      """" + dbus_name + """", """" + dbus_path + """");
        } catch (GLib.IOError e) {
            stderr.printf ("Failed to connect to DBus server: %s\n", e.message);
        }
    }
    try {
        frankenstein_client.timer_finished (timer_id, time);
    } catch (GLib.IOError e) {
        stderr.printf ("Failed to send Frankentimer finished signal: %s\n", e.message);
    }
}

static void frankenstop_callback (int stop_id) {
    if (frankenstein_client == null) {
        try {
            frankenstein_client = Bus.get_proxy_sync (BusType.SESSION,
                                                      """" + dbus_name + """", """" + dbus_path + """");
        } catch (GLib.IOError e) {
            stderr.printf ("Failed to connect to DBus server: %s\n", e.message);
        }
    }
    try {
        frankenstein_client.stop_reached (stop_id);
    } catch (GLib.IOError e) {
        stderr.printf ("Failed to send Frankenstop reached signal: %s\n", e.message);
    }
}""";
        }
    }
}

// vim: set ai ts=4 sts=4 et sw=4
