namespace Valatra {
	public delegate void RouteFunc(HTTPRequest req, HTTPResponse res) throws HTTPStatus;
  
	public abstract class Plugin : Object {
		public virtual void on_install (Valatra.App app) { }
	}

	public abstract class HTTPPlugin : Plugin {
		public HTTPPlugin () {
		}
	
		public abstract void process_request (HTTPRequest req, HTTPResponse res) throws HTTPStatus;
	}

  public class RouteWrapper : GLib.Object {
    private unowned RouteFunc func_;
	
    private Route route_;
	
	private List<HTTPPlugin> before_modules_ = new List<HTTPPlugin> ();
	private List<HTTPPlugin> after_modules_ = new List<HTTPPlugin> ();
	
    public RouteFunc func {
      get { return func_; }
      set { func_ = value;}
    }

    public Route route {
      get { return route_; }
      set { route_ = value; }
    }
	
    public RouteWrapper(Route? r, RouteFunc f) {
		this.func_ = f;
		this.route_ = r;
    }
	
	public RouteWrapper before (HTTPPlugin m) {
		before_modules_.append (m);
		return this;
	}
	
	public RouteWrapper after (HTTPPlugin m) {
		after_modules_.append (m);
		return this;
	}
	
	public HTTPResponse process_request (HTTPRequest request) throws HTTPStatus {
		var res =  new HTTPResponse();
		
		foreach(var m in this.before_modules_) {
			m.process_request (request, res);
		}
		this.func_(request, res);
		foreach(var m in this.after_modules_) {
			m.process_request (request, res);
		}
		return res;
	}
  }

	public errordomain HTTPStatus {
		STATUS,
		BAD_REQUEST,
		NOT_FOUND
	}

  public class StatusWrapper : GLib.Object {
    private unowned RouteFunc func_;
    private int status_;

    public RouteFunc func {
      get { return func_; }
      set { func_ = value;}
    }

    public int status {
      get { return status_; }
      set { status_ = value; }
    }

    public StatusWrapper(int s, RouteFunc f) {
      func_ = f;
      status_ = s;
    }
  }

  public class App : GLib.Object {

    private uint16 port_ = 3000;
    private SocketService server;
	
	private HashTable<string, Plugin> plugins_;
	private int _plugin_id_counter = 0;
	
    public Cache cache;

    /* hacky: 7 is the size of HTTP_METHODS */
    private Array<RouteWrapper> routes[7];

    private Array<StatusWrapper> status_handles;

    public uint16 port {
      get { return port_; }
      set {
        port_ = value;
        try {
          server.add_inet_port(value, null);
        } catch(Error e) {
          critical ("port.set: %s", e.message);
        }
      }
    }

    public App() {
	  plugins_ = new HashTable<string, Plugin> (str_hash, str_equal);
      server = new SocketService();
      cache = new Cache();

      status_handles = new Array<StatusWrapper>();

      for(int i = 0; i < HTTP_METHODS.length; ++i) {
        routes[i] = new Array<RouteWrapper> ();
      }

    }
	
	public T? get_plugin <T> (string id) {
		return (T)plugins_.get (id);
	}
	
	public string use (Plugin plugin, string? id = null) {
		string plugin_id = id;
		
		if (plugin_id == null)
			plugin_id = "plugin-%d".printf (_plugin_id_counter++);
			
		this.plugins_.insert (plugin_id, plugin);
		
		plugin.on_install (this);
		return plugin_id;
	}
		
    public void on(int stat, RouteFunc func) {
      status_handles.append_val (new StatusWrapper(stat, func));
    }

	public StatusWrapper? get_status_handler (int stat) {
		StatusWrapper? result = null;
		var size = status_handles.length;
		
		for(var i = 0; i < size; ++i) {
			var handle = status_handles.index (i);

			if(handle.status == stat) {
				result = handle;
				break;
			}
		}

		return result;
    }
	
    /* probably not a good idea to override get... */
    public new RouteWrapper get(string route, RouteFunc func) {
      return this.route("GET", route, func);
    }

    public RouteWrapper post(string route, RouteFunc func) {
      return this.route("POST", route, func);
    }

    public RouteWrapper put(string route, RouteFunc func) {
      return this.route("PUT", route, func);
    }

	public RouteWrapper delete (string route, RouteFunc func) {
      return this.route("DELETE", route, func);
    }
	
    public RouteWrapper? route(string meth, string path, RouteFunc func) {

      int index = -1;
      for(int i = 0; i < HTTP_METHODS.length; ++i) {
        if(meth == HTTP_METHODS[i]) {
          index = i;
        }
      }

      if(index == -1) {
        critical ("route: Bad method: %s", meth);
        return null;
      }

      var route = new Route(path);
      debug ("Creating %s \"%s\"", meth, route.route);
	  var wrapper = new RouteWrapper(route, func);
      routes[index].append_val (wrapper);
	  
	  return wrapper;
    }

    public async virtual bool start() {
        server.incoming.connect( (conn) => {
          InetSocketAddress addr;
          try {
            addr = (InetSocketAddress)conn.get_remote_address();
          } catch(Error e) {
            critical ("start.incoming: %s", e.message);
            return false;
          }

          process_request.begin (conn);

          return true;
        });

        message ("Starting Valatra server on port %d...", port_);

        server.start();
        new MainLoop().run();

        return true;
    }

    private HTTPResponse get_status_handle (int stat, HTTPRequest req) {
		var res = new HTTPResponse.with_status(stat, stat.to_string());
		var handle = get_status_handler (stat);

		if(handle == null) {
			res.type ("html");
			res.body = @"<h1>$stat</h1>";
		} else {
			try {
				handle.func(req, res);
			} catch(HTTPStatus stat) {
				res.body = "Sorry, something just exploded";
			}
		}

		return res;
    }

    private async void process_request(SocketConnection conn) {
      try {
        var dos = new DataOutputStream(conn.output_stream);

        var request = new HTTPRequest(conn);
		
		var data = new ByteArray();
		uint8[] buf = new uint8[100];
		
        while(true) {
			try {
				ssize_t ret = conn.socket.receive(buf);

				if(ret > 0) {
					data.append (buf[0:ret]);
				}

				if(ret < 100) {
					break;
				}
			} catch (Error e) {
				if (!(e is IOError.WOULD_BLOCK))
					throw e;
			}
        }
		
		// ensure string is null terminated
		data.append (new uint8[] {0});
		
        var req_str = (string)data.data;

	
        while(true) {
          if(req_str == "" || req_str == null) {
            break;
          }
          var lines = req_str.split("\r\n", 2);
          req_str = lines[1];

          if(lines[0] == null) {
            break;
          } else if(lines[0] == "") {
            request.accept_body = true;
            request.parse(lines[1]);
            break;
          } else {
            request.parse(lines[0]);
          }
        }

        request.app = this;

		debug ("processing request: '%s'", request.uri);
		
        // check cache first
        var etag = request.headers["If-None-Match"];
        if(etag != null) {
          var ent = cache[request.path];
          // cache hit
          if(ent != null && ent.etag == etag) {
            var rsp = new HTTPResponse.with_status(304, "Not modified");
            rsp.headers["Etag"] = etag;
            rsp.create(dos);
            return;
          }
        }

        int index = -1;
        for(int i = 0; i < HTTP_METHODS.length; ++i) {
          if(request.method == HTTP_METHODS[i]) {
            index = i;
          }
        }

        if(index == -1) {
          critical ("process_request: bad method: %s", request.method);

          var r = get_status_handle(400, request);

          r.create(dos);
          return;
        }

        unowned Array<RouteWrapper> array = routes[index];
        RouteWrapper wrap = null;

        for(int i=0; i < array.length; i++) {
			var elem = array.index (i);	
          if(elem.route.matches(request)) {
            wrap = elem;
            break;
          }
        }

        HTTPResponse res = null;

        if(wrap != null) {
          try {
			res = wrap.process_request (request);
          } catch(HTTPStatus stat) {
			int code;
			
			if (stat is HTTPStatus.BAD_REQUEST) {
				code = 504;
			} else if (stat is HTTPStatus.NOT_FOUND) {
				code = 404;
			} else {
				code = int.parse(stat.message);
			}
            res = get_status_handle (code, request);
          }
        } else {
          res = get_status_handle (404, request);
        }

        res.create(dos);
      } catch (Error e) {
        critical ("process_request(): %s", e.message);
      }
    }
  }
}

