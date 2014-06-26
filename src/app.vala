namespace Valatra {
  public delegate void RouteFunc(HTTPRequest req, HTTPResponse res) throws HTTPStatus;

  private class RouteWrapper : GLib.Object {
    private unowned RouteFunc func_;
    private Route route_;

    public RouteFunc func {
      get { return func_; }
      set { func_ = value;}
    }

    public Route route {
      get { return route_; }
      set { route_ = value; }
    }

    public RouteWrapper(Route? r, RouteFunc f) {
      func_ = f;
      route_ = r;
    }
  }

  public errordomain HTTPStatus {
    STATUS
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
          stderr.printf("App.port.set: %s\n", e.message);
        }
      }
    }

    public App() {
      server = new SocketService();
      cache = new Cache();

      status_handles = new Array<StatusWrapper>();

      for(int i = 0; i < HTTP_METHODS.length; ++i) {
        routes[i] = new Array<RouteWrapper> ();
      }

    }

    public void on(int stat, RouteFunc func) {
      status_handles.append_val (new StatusWrapper(stat, func));
    }

    /* probably not a good idea to override get... */
    public new void get(string route, RouteFunc func) {
      this.route("GET", route, func);
    }

    public void post(string route, RouteFunc func) {
      this.route("POST", route, func);
    }

    public void put(string route, RouteFunc func) {
      this.route("PUT", route, func);
    }

    public void route(string meth, string path, RouteFunc func) {

      int index = -1;
      for(int i = 0; i < HTTP_METHODS.length; ++i) {
        if(meth == HTTP_METHODS[i]) {
          index = i;
        }
      }

      if(index == -1) {
        stderr.printf("App.route(): Bad method: %s\n", meth);
        return;
      }

      var route = new Route(path);
      stdout.printf("Creating %s \"%s\"\n", meth, route.route);
	  routes[index].append_val (new RouteWrapper(route, func));
    }

    public async bool start() {

        server.incoming.connect( (conn) => {
          InetSocketAddress addr;
          try {
            addr = (InetSocketAddress)conn.get_remote_address();
          } catch(Error e) {
            stderr.printf("App.start().incoming: %s\n", e.message);
            return false;
          }

          process_request.begin (conn);

          return true;
        });

        stdout.printf("Starting Valatra server on port %d...\n", port_);

        server.start();
        new MainLoop().run();

        return true;
    }

    private HTTPResponse get_status_handle(int stat, HTTPRequest req) {
      var res = new HTTPResponse.with_status(stat, stat.to_string());
      int index = -1;

      var size = status_handles.length;
      for(var i = 0; i < size; ++i) {
        var handle = status_handles.index (i);
        if(handle.status == stat) {
          index = i;
          break;
        }
      }

      if(index == -1) {
        res.type("html");
        res.body = @"<h1>$stat</h1>";
      } else {
        try {
          status_handles.index (index).func(req, res);
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

        StringBuilder sb = new StringBuilder();

        while(true) {
          uint8[] buf = new uint8[100];
          ssize_t ret = conn.socket.receive(buf);

          if(ret > 0) {
            sb.append((string)buf);
          }

          if(ret < 100) {
            break;
          }
        }

        var req_str = sb.str;

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
          stderr.printf("App.process_request(): Bad method: %s\n", request.method);

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
          res = new HTTPResponse();
          try {
            wrap.func(request, res);
          } catch(HTTPStatus stat) {
            res = get_status_handle(int.parse(stat.message), request);
          }
        } else {
          res = get_status_handle(404, request);
        }

        res.create(dos);
      } catch (Error e) {
        stderr.printf("App.process_request(): %s\n", e.message);
      }
    }
  }
}

