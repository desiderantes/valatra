namespace Valatra.Json {
	public string? stringify_array (Array<Object>? array, bool serialize_nulls = false, int padleft = 0) {
		if (array == null)
			return null;
			
		var sb = new StringBuilder ();
		sb.append ("[ ");
		
		for (int i = 0; i < array.length; i++) {
			var item = array.index (i);
			if (i > 0) {
				sb.append_c (',');
			}
			
			sb.append (stringify (item, serialize_nulls, padleft));
		}
		
		sb.append_printf (" ]\n");
		return sb.str;
	}
	
	public string? stringify (Object? instance, bool serialize_nulls = false, int padleft = 0) {
		if (instance == null)
			return null;
		
		var sb = new StringBuilder ();

		sb.append ("{\n");
		
		string pad = string.nfill (padleft + 1, '\t');
		var type = instance.get_type ();
		var cl = (ObjectClass) type.class_ref ();
		bool first = true;
		
		foreach (ParamSpec  prop in cl.list_properties ()) {
			string data;
			var value = Value (prop.value_type);
			
			instance.get_property (prop.name, ref value);
			
			if (value.holds (typeof(Object)) == false 
				&& value.holds (typeof (Array)) == false
				&& (prop.flags & ParamFlags.READWRITE) != ParamFlags.READWRITE) {
				continue;
			}
		
			if (value.holds (typeof(Object))) {
				data = stringify (value.get_object (), serialize_nulls, padleft + 1);
			} else if (value.holds (typeof (Array))) {
				data = stringify_array ((Array<Object>?)value.get_pointer (), serialize_nulls, padleft + 1);
			} else {
				data = value_to_json (value);
			}
			
			if (serialize_nulls || data != null) {
				if (first) {
					first = false;
				} else {
					sb.append (",\n");
				}
				sb.append_printf ("%s\"%s\": %s", pad, prop.name, data ?? "null");
			}
		}
		sb.append_printf ("\n%s} ", padleft > 0 ? string.nfill (padleft, '\t') : "");
	
		/* stderr.printf ("\n\nD4A.Json.Stringfy:\n%s\n\n", sb.str); */
		
		return sb.str;
	}
		
	private string? value_to_json (Value value) {
		if (value.type_name () == "gchararray") {
			if (value.get_string () == null)
				return null;
			else
				return "\"%s\"".printf (value.get_string ());
		} else if (value.type_name () == "gchar") {
			return "\"%c\"".printf (value.get_char ());
		} else if (value.type_name () == "gint") {
			return "%d".printf (value.get_int ());				
		} else if (value.type_name () == "glong") {
			return "%ld".printf (value.get_long ());
		} else if (value.type_name () == "gdouble") {
			return "%g".printf (value.get_double ());
		} else if (value.type_name () == "gfloat") {
			return "%f".printf (value.get_float ());
		} else if (value.type_name () == "gboolean") {
			return "%s".printf (value.get_boolean () ? "true" : "false");			
		} else {
			critical ("value_to_json: unsupported value type %s", value.type_name ());
		}
		
		return null;
	}
}