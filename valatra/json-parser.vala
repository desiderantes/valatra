namespace Valatra.Json {
	public errordomain ParseError {
		SYNTAX,
		EOF,
		OBJECT_INSTANCE
	}

    [Flags]
    public enum ParserOptions {
        DEFAULT = 0,
        ALLOW_MISSING_PROPERTIES = 1
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
	
	private abstract class ValueToken: JsonToken {
	}
	
	private class StringToken: ValueToken {
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
	
	private class BooleanToken: ValueToken {
		public bool value;
		
		public BooleanToken () {
		}
		
		public BooleanToken.with_value (bool value) {
			this.value = value;
		}
		
		public override string to_string () {
			return "%s: %s".printf (base.to_string (), value ? "true" : "false");
		}
		
		public override string to_json (string sep = " ") {
			return "%s".printf (value ? "true" : "false");
		}
	}
	
	private class NumberToken: ValueToken {
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
		private ParserOptions _parser_options = ParserOptions.DEFAULT;
        
		public StringToken? name = null;
		
        public TupleToken (ParserOptions parser_options) {
            this._parser_options = parser_options;
        }
        
		public JsonToken? value {
			get {
				return _value;
			}
			set {
				_value = value;
				if (this.owner is ObjectToken) {
					var obj = (ObjectToken)this.owner;
					
					if (obj.instance != null) {
						var cl = (ObjectClass) obj.instance.get_type ().class_ref ();
						var prop_spec = cl.find_property (name.value);
						
						if (prop_spec == null) {
                            if ((this._parser_options & ParserOptions.ALLOW_MISSING_PROPERTIES) != ParserOptions.ALLOW_MISSING_PROPERTIES) {
                                critical ("Unknown property %s: %s (%p)", name.value, _value.get_type ().name (), _value);
                            }
						} else {
							if (_value is NumberToken) {
								var val = ((NumberToken)value).value;
								//debug ("val %s(%p).%s = %f (%p)",  obj.instance.get_type ().name (), obj.instance, name.value, val, &val);
								if (prop_spec.value_type.name () == "gint") {
									obj.instance.set (name.value, (int) val);
								} else if (prop_spec.value_type.name () == "guint") {
									obj.instance.set (name.value, (uint) val);
								} else if (prop_spec.value_type.name () == "gulong") {
									obj.instance.set (name.value, (uint) val);
								} else if (prop_spec.value_type.name () == "glong") {
									obj.instance.set (name.value, (long) val);
								} else {
									obj.instance.set (name.value, (double) val);
								}
								
							} else if (_value is StringToken) {
								string val = (string) ((StringToken)value).value;
								//debug ("valstr %s(%p).%s = %s (%p)",  obj.instance.get_type ().name (), obj.instance, name.value, val, val);
								if (prop_spec.value_type.is_enum ()) {
									var ecl = (EnumClass) prop_spec.value_type.class_ref ();
									unowned EnumValue? eval = ecl.get_value_by_nick (val);
									if (eval != null)
										obj.instance.set (name.value, eval.value);
									else {
										critical ("Unsupported enum value: %s (%p)", val, prop_spec.value_type.name ());
									}
								} else {
									obj.instance.set (name.value, val);
								}
							} else if (_value is ObjectToken) {
								obj.instance.set (name.value, (Object) ((ObjectToken)value).instance);
							} else if (_value is BooleanToken) {
								obj.instance.set (name.value, (bool) ((BooleanToken)value).value);
							} else if (_value is ArrayToken) {
								//critical ("Unsupported value type: %s (%p)", _value.get_type ().name (), _value);
							} else {
								critical ("Unsupported value type: %s (%p)", _value.get_type ().name (), _value);
							}
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
	
	[CCode(has_target=false)]
	public delegate Object? ParserClassFactory (Object? owner, string? prop_name, int index = -1) throws Error;

	public static Object? standard_class_factory (Object? owner, string? prop_name, int index = -1) throws Error {
		Type? type = null;
		Object? instance = null;
	
		if (owner != null) {
			if (prop_name != null) {
				if (index == -1) {
					// Object property
					var prop = ((ObjectClass)owner.get_type ().class_ref ()).find_property (prop_name);
					if (prop != null) {
						type = prop.value_type;
					}
				} else {
					// Array property
					unowned Array<Object> a = null;
					
					owner.get (prop_name, &a);
					if (a != null) {
						instance = a.index ((uint)index);
					} else {
						throw new ParseError.OBJECT_INSTANCE ("standard_class_factory: array instance is null for property: %s.".printf (prop_name));
					}
				}
			} else {
				throw new ParseError.OBJECT_INSTANCE ("standard_class_factory: prop_name (%s) cannot be null and should be a valid property name of object %s (%p).".printf (prop_name, owner.get_type ().name (), owner));
			}
		} else {
			throw new ParseError.OBJECT_INSTANCE ("standard_class_factory: owner cannot be null.");
		}

		if (type != null && instance == null) {
			instance = Object.@new (type);
		}
		
		return instance;
	}
	
	public Object? parse (string? data, Object? root_instance = null, ParserOptions parser_options = ParserOptions.DEFAULT, ParserClassFactory class_factory = standard_class_factory) throws Error {
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
						var obj = new ObjectToken ();
						string prop_name = null;
						Object? owner = null;
						int index = -1;
						//int dbg =-1;
                        
						if (current is TupleToken) {
							var t = (TupleToken)current;
							if (t.name != null) {
								prop_name = t.name.value;
							}
							owner = ((ObjectToken)current.owner).instance;
						} else if (current is ArrayToken) {
							var a = (ArrayToken)current;
							
							index = (int) a.values.length ();
                            //dbg = index;
							if (a.owner is TupleToken) {
								prop_name = ((TupleToken)a.owner).name.value;
								owner = ((ObjectToken)((TupleToken)a.owner).owner).instance;
							} else if (a.owner is ObjectToken) {
								owner = ((ObjectToken)a.owner).instance;
							}
						}
					
						if (current == null) {
							if (root_instance == null) {
								obj.instance = class_factory (null, prop_name, index);
                                //debug ("%s[%d] = %p", prop_name, index, obj.instance);
							} else {
								obj.instance = root_instance;
							}
						} else {
							obj.instance = class_factory (owner, prop_name, index);
                            //debug ("%s[%d,%d] = %p", prop_name, index, dbg, obj.instance);
						}
						
						if (obj.instance == null) {
							throw new ParseError.OBJECT_INSTANCE ("Can't create %s property name '%s' of object type %s (%p)".printf (
								index == -1 ? "object instance for" : "instance for array element %u of".printf (index),
								prop_name == null ? "(null)" : prop_name, 
								owner == null ? "(null)" : owner.get_type ().name (),
								owner));
						}

						obj.start = i;
						obj.owner = current;
						current = obj;
						i++;
					} else if (ch == ':') {
						if (!(current is StringToken)) {
							throw new ParseError.SYNTAX ("syntax error parsing tuple, unexpected ':'");
						}
						if (!(current.owner is ObjectToken)) {
							throw new ParseError.SYNTAX ("syntax error parsing tuple, owner is not an Object: %s (%s)".printf (current.owner == null ? "(null)" : current.owner.get_type ().name (), current.to_string ()));
						}
						var token = new TupleToken (parser_options);
						token.start = current.start;
						token.name = (StringToken)current;
						token.owner = current.owner;
						current.owner = token;
						current = token;
						i++;
					} else if (ch == '}') {
						current.end = i;
						var token = current;
						current = current.owner;
						current.end = i;
						i++;
						if (current is TupleToken) {
							var t = (TupleToken) current;
							t.value = token;
							current = current.owner;
						} else {
							if (!(current is ObjectToken)) // empty object
								throw new ParseError.SYNTAX ("syntax error %s".printf (current == null ? "(null)" : current.to_string ()), i);
						}
					} else if (ch == '[') {
						var token = new ArrayToken ();
						token.start = i;
						token.owner = current;
						current = token;
						i++;
					} else if (ch == ']') {
						var token = current;
						token.end = i;
						current = current.owner;
						current.end = i;
						i++;
						if (current is ArrayToken) {
                            var a = (ArrayToken)current;
                            a.values.append (token);
						} else {
							if (!(token is ArrayToken)) // empty array
								throw new ParseError.SYNTAX ("unexpected ']' %s", current.get_type ().name ());
						}
						
					} else if (ch == ',') {
						var token = current;
						current.end = i;
						current = current.owner;
						current.end = i;
						i++;
						if (current is TupleToken) {
							var tuple = (TupleToken) current;
							tuple.value = token;
							current = current.owner;
							((ObjectToken)current).values.append (tuple);
						} else if (current is ArrayToken) {
                            var a = (ArrayToken)current;
								
                            a.values.append (current);
						} else {
							throw new ParseError.SYNTAX ("syntax error unexpected ',' %s".printf (current.to_string ()));
						}
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
					} else if (ch == 't' || ch == 'f') {
						var token = new BooleanToken ();
						token.start = i;
						token.value = parse_boolean (data, ref i);
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
		return ((ObjectToken)current).instance;
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
	
	private bool parse_boolean (string data, ref int i) throws Error {
		if (i == data.length) {
			throw new ParseError.EOF ("Unexpected EOF");
		}
		char ch = data[i];
		var sb = new StringBuilder ();
		
		while (ch.isalpha ()) {
			sb.append_c (ch);
			i++;
			if (i == data.length) {
				throw new ParseError.EOF ("Unexpected EOF");
			}
				
			ch = data[i];
		}
		
		if (sb.str == "true")
			return true;
		else if (sb.str == "false")
			return false;
		else
			throw new ParseError.SYNTAX ("syntax error parsing boolean");			
	}
}