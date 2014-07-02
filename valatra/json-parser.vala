namespace Valatra.Json {
	public errordomain ParseError {
		SYNTAX,
		EOF,
		UNKNOWN_OBJECT_TYPE
	}

	private abstract class JsonToken : Object {
		public int start;
		public int end;
		
		public JsonToken? owner = null;
		
		public virtual string to_string () {
			Type? type = this.get_type ();
			assert (type != null);
				
			var type_name = type.name ();
			return "%s (%d-%d)".printf (type_name, start, end);
		}
		
		public abstract string to_json (string sep = " ");
	}
	
	private class StringToken: JsonToken {
		public string value;
		
		public StringToken () {
		}
		
		public StringToken.with_value (string value) {
			this.value = value;
		}
		
		public override string to_string () {
			return "%s: %s".printf (base.to_string (), value);
		}
		
		public override string to_json (string sep = " ") {
			return "\"%s\"".printf (value);
		}
	}
	
	private class NumberToken: JsonToken {
		public double value;
		
		public NumberToken () {
		}
		
		public NumberToken.with_value (double value) {
			this.value = value;
		}
		
		public override string to_string () {
			return "%s: %g".printf (base.to_string (), value);
		}
		
		public override string to_json (string sep = " ") {
			return "%g".printf (value);
		}
	}
	
	private class ObjectToken : JsonToken {
		public List<TupleToken> values = new List<TupleToken> ();
		public Object? instance = null;
		
		public override string to_json (string sep = " ") {
			var sb = new StringBuilder ();

			sb.append ("{");
			sb.append (sep);
			bool first = true;
			foreach (var value in values) {
				if (!first) {
					sb.append (",");
					sb.append (sep);
				} else {
					first = false;
				}
				sb.append (value.to_json ());
			}
			sb.append (sep);
			sb.append ("}");
			sb.append (sep);
			return sb.str;
		}
	}

	private class ArrayToken : JsonToken {
		public List<JsonToken> values = new List<JsonToken> ();
		
		public override string to_json (string sep = " ") {
			var sb = new StringBuilder ();

			sb.append ("[");
			sb.append (sep);
			bool first = true;
			foreach (var value in values) {
				if (!first) {
					sb.append (",");
					sb.append (sep);
				} else {
					first = false;
				}
				sb.append (value.to_json ());
			}
			sb.append ("]");
			sb.append (sep);
			return sb.str;
		}
	}

	private class TupleToken : JsonToken {
		private JsonToken? _value = null;
		
		public StringToken? name = null;
		
		public JsonToken? value {
			get {
				return _value;
			}
			set {
				_value = value;
				if (this.owner is ObjectToken) {
					var obj = (ObjectToken)this.owner;
					if (obj.instance != null) {
						if (_value is NumberToken) {
							obj.instance.set (name.value, (double) ((NumberToken)value).value);
						} else if (_value is StringToken) {
							obj.instance.set (name.value, (string) ((StringToken)value).value);
						} else if (_value is ObjectToken) {
							obj.instance.set (name.value, (Object) ((ObjectToken)value).instance);
						} else {
							critical ("Unsupported value type: %s (%p)", _value.get_type ().name (), _value);
						}
					}
				}
			}
		}
		
		public override string to_string () {
			return "%s: [%s] = [%s]".printf (base.to_string (), name == null ? "(null)" : name.to_string (), value == null ? "(null)" : value.to_string ());
		}
		
		public override string to_json (string sep = " ") {
			return "%s: %s".printf (name.to_json (), value == null ? "null" : value.to_json ());
		}
	}
	
	public delegate Object? ParserClassFactory (Type type, string? prop_name);

	public static Object? standard_class_factory (Type type, string? prop_name) {
		var instance = Object.@new (type);
		return instance;
	}
	
	public T? parse<T> (string? data, ParserClassFactory class_factory = standard_class_factory) throws Error {
		JsonToken current = null;
		int i = 0;
		
		if (data == null)
			return null;
			
		while (i < data.length) {
			try {
				skip_spaces (data, ref i);
				
				if (i < data.length) {
					char ch = data[i];
					
					if (ch == '{') {
						var token = new ObjectToken ();
						string prop_name = null;
						Type? type = null;
						
						if (current == null) {
							type = typeof (T);
						}
						if (current is TupleToken) {
							var t = (TupleToken)current;
							if (t.name != null)
								prop_name = t.name.value;
								
							if (t.owner is Object && prop_name != null) {
								var prop = ((ObjectClass) ((Object)((ObjectToken)current.owner).instance).get_type ().class_ref ()).find_property (prop_name);
								if (prop != null)
									type = prop.value_type;
							}
						}
						
						if (type != null) {
							token.instance = class_factory (type, prop_name);
						} else {
							throw new ParseError.UNKNOWN_OBJECT_TYPE ("Unknown object type for property name: '%s'".printf (prop_name == null ? "(null)" : prop_name));
						}
						token.start = i;
						token.owner = current;
						current = token;
						i++;
					} else if (ch == ':') {
						if (!(current is StringToken)) {
							throw new ParseError.SYNTAX ("syntax error parsing tuple, unexpected ':'");
						}
						if (!(current.owner is ObjectToken)) {
							throw new ParseError.SYNTAX ("syntax error parsing tuple, owner is not an Object");
						}
						var token = new TupleToken ();
						((ObjectToken)current.owner).values.append (token);
						token.start = current.start;
						token.name = (StringToken)current;
						token.owner = current.owner;
						current.owner = token;
						current = token;
					
						i++;
					} else if (ch == '}') {
						if (current.owner is TupleToken) {
							var owner = (TupleToken) current.owner;
							owner.value = current;
							current = owner;
						} else {
							throw new ParseError.SYNTAX ("syntax error %s".printf (current.owner.to_string ()), i);
						}
						current.end = i;
						i++;
						if (current.owner != null) {
							current = current.owner;
						} else {
							critical ("parse: current is null");
						}
					} else if (ch == '[') {
						var token = new ArrayToken ();
						token.start = i;
						token.owner = current;
						current = token;
						i++;
					} else if (ch == ']') {
						if (!(current is ArrayToken)) {
							throw new ParseError.SYNTAX ("unexpected ']'");
						}
						current.end = i;
						i++;
						if (current.owner != null) {
							current = current.owner;
						}
					} else if (ch == ',') {
						if (current.owner is TupleToken) {
							var tuple = (TupleToken) current.owner;
							tuple.value = current;
							tuple.end = i;
							current = tuple;
						} else if (current.owner is ArrayToken) {
							var array = (ArrayToken)current.owner;
							array.values.append (current);
							array.end = i;
						} else {
							throw new ParseError.SYNTAX ("syntax error unexpected ',' %s".printf (current.to_string ()));
						}
						current = current.owner;
						current.end = i;
						i++;
					} else if (ch == '"') {
						var token = new StringToken ();
						token.start = i;
						i++;
						token.value = parse_string (data, ref i);
						token.end = i;
						token.owner = current;
						current = token;
						i++;
					} else if (ch.isdigit ()) {
						var token = new NumberToken ();
						token.start = i;
						token.value = parse_double (data, ref i);
						token.end = i;
						token.owner = current;
						current = token;
					} else {
						throw new ParseError.SYNTAX ("syntax error, unexpected char '%c'".printf (ch));
					}
				}
			} catch (Error e) {
				throw new ParseError.SYNTAX ("parse error at char %d: %s".printf (i, e.message));
			}
		}
		
		if (current == null)
			return null;
			
		if (!(current is ObjectToken)) {
			throw new ParseError.SYNTAX ("Root object token not defined (%s: %p), only json with the form { ... } are currently supported".printf (current.get_type ().name (), current));
		}
		return (T?) ((ObjectToken)current).instance;
	}
	
	private void skip_spaces (string data, ref int i) throws ParseError {
		if (i == data.length) {
			return;
		}
		char ch = data[i];
		
		while (ch.isspace ()) {
			i++;
			if (i == data.length) {
				return;
			}
				
			ch = data[i];
		}
	}
	
	private string parse_string (string data, ref int i) throws ParseError {
		if (i == data.length) {
			throw new ParseError.EOF ("Unexpected EOF");
		}
		char ch = data[i];
		var sb = new StringBuilder ();
		
		while (ch != '"') {
			sb.append_c (ch);
			i++;
			if (i == data.length) {
				throw new ParseError.EOF ("Unexpected EOF");
			}
				
			ch = data[i];
		}
		
		return sb.str;
	}
	
	private double parse_double (string data, ref int i) throws Error {
		if (i == data.length) {
			throw new ParseError.EOF ("Unexpected EOF");
		}
		char ch = data[i];
		var sb = new StringBuilder ();
		bool parsing_decimals = false;
		
		while (ch.isdigit () || ch == '.') {
			if (ch == '.') {
				if (parsing_decimals) {
					throw new ParseError.SYNTAX ("syntax error parsing number");
				} else {
					parsing_decimals = true;
				}
			}
			sb.append_c (ch);
			i++;
			if (i == data.length) {
				throw new ParseError.EOF ("Unexpected EOF");
			}
				
			ch = data[i];
		}
		
		return double.parse (sb.str);
	}
}