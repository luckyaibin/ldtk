package data.def;

/**
	Derived IntGrid layers only: one "write instruction" of an auto-layer rule.
	A rule can have several outputs, ie. it can write multiple cells at once.

	For every matched cell, one value is picked from `values` (randomly, using the layer seed) and written
	in the cell located at (`offsetX`,`offsetY`), relatively to the matched cell.

	NOTE: this is an editor-only data type, serialized through reflection (see AutoLayerRuleDef.toJson),
	so older LDtk versions simply ignore it.
**/
class RuleOutputDef {
	public var values : Array<Int> = [];
	public var offsetX = 0;
	public var offsetY = 0;

	public function new() {}

	public inline function isEmpty() return values.length==0;

	public function toJson() : Dynamic {
		return {
			values: values.copy(),
			offsetX: offsetX,
			offsetY: offsetY,
		};
	}

	public static function fromJson(json:Dynamic) : RuleOutputDef {
		var o = new RuleOutputDef();
		var rawValues : Array<Dynamic> = Reflect.field(json, "values");
		if( rawValues!=null )
			for(v in rawValues)
				if( M.isValidNumber(v) )
					o.values.push( Std.int(v) );
		o.offsetX = JsonTools.readInt(Reflect.field(json, "offsetX"), 0);
		o.offsetY = JsonTools.readInt(Reflect.field(json, "offsetY"), 0);
		return o;
	}
}
