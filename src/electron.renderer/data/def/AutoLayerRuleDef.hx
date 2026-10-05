package data.def;

class AutoLayerRuleDef {
	#if heaps // Required to avoid doc generator to explore code too deeply

	@:allow(data.def.LayerDef, data.Definitions)
	public var uid(default,null) : Int;

	public var tileRectsIds : Array< Array<Int> > = [];
	public var chance : Float = 1.0;
	public var breakOnMatch = true;
	public var size(default,null): Int;
	var pattern : Array<Int> = [];
	public var alpha = 1.;
	public var outOfBoundsValue : Null<Int>;
	public var flipX = false;
	public var flipY = false;
	public var active = true;
	public var tileMode : ldtk.Json.AutoLayerRuleTileMode = Single;
	public var pivotX = 0.;
	public var pivotY = 0.;
	public var xModulo = 1;
	public var yModulo = 1;
	public var xOffset = 0;
	public var yOffset = 0;
	public var tileXOffset = 0;
	public var tileYOffset = 0;
	public var tileRandomXMin = 0;
	public var tileRandomXMax = 0;
	public var tileRandomYMin = 0;
	public var tileRandomYMax = 0;
	public var checker : ldtk.Json.AutoLayerRuleCheckerMode = None;

	// Derived IntGrid layers only: cells & values to write in the destination layer (see RuleOutputDef)
	public var outputs : Array<RuleOutputDef> = [];

	// Dual-grid mode (editor-only, see Const.DUAL_GRID_MASK_COUNT): instead of matching the pattern at each layer
	// cell, this rule computes a 0-15 mask of the 4 cells around each grid CORNER (bit 1=NW, 2=NE, 4=SW, 8=SE) and
	// renders the tile(s) stored in tileRectsIds[mask] at that corner position (using tileXOffset/tileYOffset).
	// Typical use: one rule per terrain, with a standard 4x4 "windmill" dual-grid tileset.
	public var dualGrid = false;

	public var invalidated = false;

	var perlinActive = false;
	public var perlinSeed : Int;
	public var perlinScale : Float = 0.2;
	public var perlinOctaves = 2;
	var _perlin(get,null) : Null<hxd.Perlin>;

	var explicitlyRequiredValues : Array<Int> = [];

	public var radius(get,never) : Int; inline function get_radius() return size<=1 ? 1 : Std.int(size*0.5);

	public function new(uid, size=3) {
		if( !isValidSize(size) )
			throw 'Invalid rule size ${size}x$size';

		this.uid = uid;
		this.size = size;
		perlinSeed = Std.random(9999999);
		initPattern();
	}

	public function updateUsedValues() {
		explicitlyRequiredValues = [];
		for(v in pattern)
			if( v>0 && v!=Const.AUTO_LAYER_ANYTHING && !explicitlyRequiredValues.contains(v) )
				explicitlyRequiredValues.push(v);
	}

	public inline function hasAnyPositionOffset() {
		return tileRandomXMin!=0 || tileRandomXMax!=0 || tileRandomYMin!=0 || tileRandomYMax!=0 || tileXOffset!=0 || tileYOffset!=0;
	}

	public function hasOutputValues() {
		for(o in outputs)
			if( !o.isEmpty() )
				return true;
		return false;
	}

	/** Derived IntGrid layers only: the largest absolute offset used by this rule's outputs **/
	public function getMaxOutputOffset() : Int {
		var m = 0;
		for(o in outputs) {
			m = M.imax(m, M.iabs(o.offsetX));
			m = M.imax(m, M.iabs(o.offsetY));
		}
		return m;
	}

	/**
	Dual-grid mode: the IntGrid value of the center pattern cell, ie. the "terrain" this rule renders.
	A negative value means this rule is not properly configured for dual-grid mode.
	**/
	public inline function getDualGridValue() : Int {
		var v = getPattern( Std.int(size*0.5), Std.int(size*0.5) );
		return v>0 ? v : -1;
	}

	/** Dual-grid mode: does the given IntGrid value (read from the source layer) belong to this rule's terrain? **/
	public function doesDualGridValueMatch(source:data.inst.LayerInstance, value:Int) : Bool {
		var ruleValue = getDualGridValue();
		if( ruleValue<0 )
			return false;

		if( ruleValue==Const.AUTO_LAYER_ANYTHING )
			// "Any value": any non-empty cell is part of this terrain
			return value!=0;

		if( ruleValue>999 ) {
			// Group value: the cell belongs to any IntGrid value of this group
			var inf = source.def.getIntGridValueDef(value);
			return inf!=null && inf.groupUid == Std.int(ruleValue/1000)-1;
		}

		return value==ruleValue;
	}

	/**
	Dual-grid mode: read an IntGrid value from the source layer, applying the out-of-bounds policy.
	By default, out-of-bounds cells are considered empty (value 0).
	**/
	public function readDualGridSourceValue(source:data.inst.LayerInstance, cx:Int, cy:Int) : Int {
		if( source.isValid(cx,cy) )
			return source.getIntGrid(cx,cy);
		else
			return outOfBoundsValue==null || outOfBoundsValue<0 ? 0 : outOfBoundsValue;
	}

	/**
	Dual-grid mode: 0-15 mask of the 4 cells around the TOP-LEFT corner of cell (cx,cy),
	ie. the grid vertex at pixel (cx*gridSize, cy*gridSize).
	Bits: NW=1, NE=2, SW=4, SE=8.
	**/
	public function getDualGridMask(source:data.inst.LayerInstance, cx:Int, cy:Int) : Int {
		var mask = 0;
		if( doesDualGridValueMatch(source, readDualGridSourceValue(source, cx-1, cy-1)) ) mask |= 1; // NW
		if( doesDualGridValueMatch(source, readDualGridSourceValue(source, cx  , cy-1)) ) mask |= 2; // NE
		if( doesDualGridValueMatch(source, readDualGridSourceValue(source, cx-1, cy  )) ) mask |= 4; // SW
		if( doesDualGridValueMatch(source, readDualGridSourceValue(source, cx  , cy  )) ) mask |= 8; // SE
		return mask;
	}

	/**
	Dual-grid mode: the tile rect IDs to render for the given 0-15 mask.
	If several tiles are stored in the mask slot, one is picked using the layer seed.
	**/
	public function getDualGridTileRectIdsForMask(seed:Int, mask:Int, cx:Int, cy:Int) : Array<Int> {
		if( mask<0 || mask>=tileRectsIds.length )
			return [];

		var tids = tileRectsIds[mask];
		return tids.length<=1
			? tids
			: [ tids[ dn.M.randSeedCoords(uid+seed+911, cx,cy, tids.length) ] ];
	}

	/** Perlin check at given coords **/
	public inline function isPerlinAllowedAt(seed:Int, cx:Int, cy:Int) : Bool {
		return !hasPerlin() || _perlin.perlin(seed+perlinSeed, cx*perlinScale, cy*perlinScale, perlinOctaves) >= 0;
	}

	inline function isValidSize(size:Int) {
		return size>=1 && size<=Const.MAX_AUTO_PATTERN_SIZE && size%2!=0;
	}

	inline function get__perlin() {
		if( perlinSeed!=null && _perlin==null ) {
			_perlin = new hxd.Perlin();
			_perlin.normalize = true;
			_perlin.adjustScale(50, 1);
		}

		if( perlinSeed==null && _perlin!=null )
			_perlin = null;

		return _perlin;
	}

	public inline function hasPerlin() return perlinActive;

	public function setPerlin(active:Bool) {
		if( !active ) {
			perlinActive = false;
			_perlin = null;
		}
		else
			perlinActive = true;
	}

	public function isSymetricX() {
		for( cx in 0...Std.int(size*0.5) )
		for( cy in 0...size )
			if( pattern[coordId(cx,cy)] != pattern[coordId(size-1-cx,cy)] )
				return false;

		return true;
	}

	public function isSymetricY() {
		for( cx in 0...size )
		for( cy in 0...Std.int(size*0.5) )
			if( pattern[coordId(cx,cy)] != pattern[coordId(cx,size-1-cy)] )
				return false;

		return true;
	}

	public inline function getPattern(cx,cy) {
		return pattern[ coordId(cx,cy) ];
	}

	public inline function setPattern(cx,cy,v) {
		if( !isValid(cx,cy) )
			return 0;

		pattern[ coordId(cx,cy) ] = v;
		return v;
	}

	public inline function fill(v:Int) {
		for(cx in 0...size)
		for(cy in 0...size)
			setPattern(cx,cy,v);
		updateUsedValues();
	}

	function initPattern() {
		pattern = [];
		for(i in 0...size*size)
			pattern[i] = 0;
		updateUsedValues();
	}

	@:keep public function toString() {
		return 'Rule#$uid(${size}x$size)';
	}

	public function toJson(ld:LayerDef) : ldtk.Json.AutoRuleDef {
		tidy(ld);

		var json : ldtk.Json.AutoRuleDef = {
			uid: uid,
			active: active,
			size: size,
			tileRectsIds: tileRectsIds.map( arr->arr.copy() ),
			alpha: alpha,
			chance: JsonTools.writeFloat(chance),
			breakOnMatch: breakOnMatch,
			pattern: pattern.copy(), // WARNING: could leak to undo/redo leaks if (one day) pattern contained objects
			flipX: flipX,
			flipY: flipY,
			xModulo: xModulo,
			yModulo: yModulo,
			xOffset: xOffset,
			yOffset: yOffset,
			tileXOffset: tileXOffset,
			tileYOffset: tileYOffset,
			tileRandomXMin: tileRandomXMin,
			tileRandomXMax: tileRandomXMax,
			tileRandomYMin: tileRandomYMin,
			tileRandomYMax: tileRandomYMax,
			checker: JsonTools.writeEnum(checker, false),
			tileMode: JsonTools.writeEnum(tileMode, false),
			pivotX: JsonTools.writeFloat(pivotX),
			pivotY: JsonTools.writeFloat(pivotY),
			outOfBoundsValue: outOfBoundsValue,

			invalidated: invalidated,

			perlinActive: perlinActive,
			perlinSeed: perlinSeed,
			perlinScale: JsonTools.writeFloat(perlinScale),
			perlinOctaves: perlinOctaves,
		};

		// Derived IntGrid layers: editor-only fields, absent from the ldtk.Json.AutoRuleDef haxelib definition (exported through reflection).
		// Older LDtk versions will simply ignore these extra fields.
		Reflect.setField(json, "outputs", outputs.map( o->o.toJson() ));

		// Dual-grid mode: editor-only field, only written when enabled (old LDtk versions will ignore it)
		if( dualGrid )
			Reflect.setField(json, "dualGrid", true);

		return json;
	}

	public static function fromJson(jsonVersion:String, json:ldtk.Json.AutoRuleDef) {
		// Update JSON for tileRectsIds
		if( json.tileIds!=null ) {
			json.tileRectsIds = [];
			var mode = JsonTools.readEnum(ldtk.Json.AutoLayerRuleTileMode, json.tileMode, false, Single);
			switch mode {
				case Single:
					json.tileRectsIds = json.tileIds.map( tid->[tid] );

				case Stamp:
					json.tileRectsIds = [ json.tileIds ];
			}
		}

		var r = new AutoLayerRuleDef( json.uid, json.size );
		r.active = JsonTools.readBool(json.active, true);
		r.tileRectsIds = json.tileRectsIds.copy();
		r.breakOnMatch = JsonTools.readBool(json.breakOnMatch, false); // default to FALSE to avoid breaking old maps
		r.chance = JsonTools.readFloat(json.chance);
		r.pattern = json.pattern;
		r.alpha = JsonTools.readFloat(json.alpha, 1);
		r.outOfBoundsValue = JsonTools.readNullableInt(json.outOfBoundsValue);
		r.flipX = JsonTools.readBool(json.flipX, false);
		r.flipY = JsonTools.readBool(json.flipY, false);
		r.checker = JsonTools.readEnum(ldtk.Json.AutoLayerRuleCheckerMode, json.checker, false, None);
		r.tileMode = JsonTools.readEnum(ldtk.Json.AutoLayerRuleTileMode, json.tileMode, false, Single);
		r.pivotX = JsonTools.readFloat(json.pivotX, 0);
		r.pivotY = JsonTools.readFloat(json.pivotY, 0);
		r.xModulo = JsonTools.readInt(json.xModulo, 1);
		r.yModulo = JsonTools.readInt(json.yModulo, 1);
		r.xOffset = JsonTools.readInt(json.xOffset, 0);
		r.yOffset = JsonTools.readInt(json.yOffset, 0);
		r.tileXOffset = JsonTools.readInt(json.tileXOffset, 0);
		r.tileYOffset = JsonTools.readInt(json.tileYOffset, 0);
		r.tileRandomXMin = JsonTools.readInt(json.tileRandomXMin, 0);
		r.tileRandomXMax = JsonTools.readInt(json.tileRandomXMax, 0);
		r.tileRandomYMin = JsonTools.readInt(json.tileRandomYMin, 0);
		r.tileRandomYMax = JsonTools.readInt(json.tileRandomYMax, 0);

		r.invalidated = JsonTools.readBool(json.invalidated, false);

		r.perlinActive = JsonTools.readBool(json.perlinActive, false);
		r.perlinScale = JsonTools.readFloat(json.perlinScale, 0.2);
		r.perlinOctaves = JsonTools.readInt(json.perlinOctaves, 2);
		r.perlinSeed = JsonTools.readInt(json.perlinSeed, Std.random(9999999));

		// Derived IntGrid layers (editor-only fields, see toJson)
		r.outputs = [];
		var rawOutputs : Array<Dynamic> = Reflect.field(json, "outputs");
		if( rawOutputs!=null ) {
			for(item in rawOutputs)
				if( item!=null )
					r.outputs.push( RuleOutputDef.fromJson(item) );
		}
		else {
			// Migration from the early (single output) format: outputValues + outputOffsetX/Y
			var o = new RuleOutputDef();
			var rawOutputValues : Array<Dynamic> = Reflect.field(json, "outputValues");
			if( rawOutputValues!=null )
				for(v in rawOutputValues)
					if( M.isValidNumber(v) )
						o.values.push( Std.int(v) );
			o.offsetX = JsonTools.readInt(Reflect.field(json, "outputOffsetX"), 0);
			o.offsetY = JsonTools.readInt(Reflect.field(json, "outputOffsetY"), 0);
			if( !o.isEmpty() )
				r.outputs.push(o);
		}

		// Dual-grid mode (editor-only field, see toJson)
		r.dualGrid = JsonTools.readBool(Reflect.field(json, "dualGrid"), false);

		r.updateUsedValues();

		return r;
	}



	public function resize(newSize:Int) {
		if( !isValidSize(newSize) )
			throw 'Invalid rule size ${size}x$size';

		var oldSize = size;
		var oldPatt = pattern.copy();
		var pad = Std.int( dn.M.iabs(newSize-oldSize) / 2 );

		size = newSize;
		initPattern();
		if( newSize<oldSize ) {
			// Decrease
			for( cx in 0...newSize )
			for( cy in 0...newSize )
				pattern[cx + cy*newSize] = oldPatt[cx+pad + (cy+pad)*oldSize];
		}
		else {
			// Increase
			for( cx in 0...oldSize )
			for( cy in 0...oldSize )
				pattern[cx+pad + (cy+pad)*newSize] = oldPatt[cx + cy*oldSize];
		}
	}

	inline function coordId(cx,cy) return cx+cy*size;
	inline function isValid(cx,cy) {
		return cx>=0 && cx<size && cy>=0 && cy<size;
	}

	public function trim() {
		while( size>1 ) {
			var emptyBorder = true;
			// Horizontal borders
			for( cx in 0...size )
				if( pattern[coordId(cx,0)]!=0 || pattern[coordId(cx,size-1)]!=0 ) {
					emptyBorder = false;
					break;
				}

			// Vertical borders
			if( emptyBorder )
				for( cy in 0...size )
					if( pattern[coordId(0,cy)]!=0 || pattern[coordId(size-1,cy)]!=0 ) {
						emptyBorder = false;
						break;
					}

			if( emptyBorder )
				resize(size-2);
			else
				break;
		}
	}

	public function isEmpty() {
		for(v in pattern)
			if( v!=0 )
				return false;

		if( dualGrid ) {
			for(slot in tileRectsIds)
				if( slot.length>0 )
					return false;
			return true;
		}

		return tileRectsIds.length==0 && !hasOutputValues();
	}

	public function isUsingUnknownIntGridValues(ld:LayerDef) {
		if( ld.type!=IntGrid )
			throw "Invalid layer type";

		for(v in pattern) {
			if( v==0 )
				continue;

			v = M.iabs(v);

			if( v<=999 && !ld.hasIntGridValue(v) )
				return true;

			if( v>999 && v!=Const.AUTO_LAYER_ANYTHING && !ld.hasIntGridGroup( ld.resolveIntGridGroupUidFromRuleValue(v) ) )
				return true;
		}

		return false;
	}

	public function isRelevantInLayer(sourceLi:data.inst.LayerInstance) {
		for(v in explicitlyRequiredValues)
			if( !sourceLi.containsIntGridValueOrGroup(v) )
				return false;
		return true;
	}

	public function isRelevantInLayerAt(sourceLi:data.inst.LayerInstance, cx:Int, cy:Int) {
		for(v in explicitlyRequiredValues) {
			if( !sourceLi.containsIntGridValueOrGroup(v) )
				return false;
			else if( size==1 && !sourceLi.hasIntGridValueInArea(v,cx,cy) )
				return false;
			else if( size>1
				&& !sourceLi.hasIntGridValueInArea(v,cx-radius,cy-radius)
				&& !sourceLi.hasIntGridValueInArea(v,cx+radius,cy-radius)
				&& !sourceLi.hasIntGridValueInArea(v,cx+radius,cy+radius)
				&& !sourceLi.hasIntGridValueInArea(v,cx-radius,cy+radius) )
					return false;
		}
		return true;
	}

	public function matches(li:data.inst.LayerInstance, source:data.inst.LayerInstance, cx:Int, cy:Int, dirX=1, dirY=1) {
		if( tileRectsIds.length==0 && !hasOutputValues() )
			return false;

		if( chance<=0 || chance<1 && dn.M.randSeedCoords(li.seed+uid, cx,cy, 100) >= chance*100 )
			return false;

		if( hasPerlin() && _perlin.perlin(li.seed+perlinSeed, cx*perlinScale, cy*perlinScale, perlinOctaves) < 0 )
			return false;

		// Rule check
		var value : Null<Int> = 0;
		var valueInf : Null<data.DataTypes.IntGridValueDefEditor> = null;
		var radius = Std.int( size/2 );
		for(px in 0...size)
		for(py in 0...size) {
			var coordId = px + py*size;
			if( pattern[coordId]==0 )
				continue;

			value = source.isValid( cx+dirX*(px-radius), cy+dirY*(py-radius) )
				? source.getIntGrid( cx+dirX*(px-radius), cy+dirY*(py-radius) )
				: outOfBoundsValue;

			if( value==null )
				return false;

			if( dn.M.iabs( pattern[coordId] ) == Const.AUTO_LAYER_ANYTHING ) {
				// "Anything" checks
				if( pattern[coordId]>0 && value==0 )
					return false;

				if( pattern[coordId]<0 && value!=0 )
					return false;
			}
			else if( dn.M.iabs( pattern[coordId] ) > 999 ) {
				// Group checks
				valueInf = source.def.getIntGridValueDef(value);
				if( pattern[coordId]>0 && ( valueInf==null || valueInf.groupUid != Std.int(pattern[coordId]/1000)-1 ) )
					return false;

				if( pattern[coordId]<0 && ( valueInf!=null && valueInf.groupUid == Std.int(-pattern[coordId]/1000)-1 ) )
					return false;
			}
			else {
				// Specific value checks
				if( pattern[coordId]>0 && value != pattern[coordId] )
					return false;

				if( pattern[coordId]<0 && value == -pattern[coordId] )
					return false;
			}
		}
		return true;
	}

	public function tidy(ld:LayerDef) {
		var anyFix = false;

		trim();

		if( flipX && isSymetricX() ) {
			App.LOG.add("tidy", 'Fixed X symetry of Rule#$uid');
			flipX = false;
			anyFix = true;
		}

		if( flipY && isSymetricY() ) {
			App.LOG.add("tidy", 'Fixed Y symetry of Rule#$uid');
			flipY = false;
			anyFix = true;
		}

		if( xModulo==1 && yModulo==1 && checker!=None ) {
			App.LOG.add("tidy", 'Fixed checker mode of Rule#$uid');
			checker = None;
			anyFix = true;
		}

		if( xModulo==1 && checker==Horizontal ) {
			App.LOG.add("tidy", 'Fixed checker mode of Rule#$uid');
			checker = yModulo>1 ? Vertical : None;
			anyFix = true;
		}

		if( yModulo==1 && checker==Vertical ) {
			App.LOG.add("tidy", 'Fixed checker mode of Rule#$uid');
			checker = xModulo>1 ? Horizontal : None;
			anyFix = true;
		}

		var sourceLd = ld.autoSourceLd!=null ? ld.autoSourceLd : ld;
		if( outOfBoundsValue!=null && outOfBoundsValue!=0 && !sourceLd.hasIntGridValue(outOfBoundsValue) ) {
			App.LOG.add("tidy", 'Fixed lost outOfBoundsValue: $outOfBoundsValue');
			outOfBoundsValue = null;
		}

		// Derived IntGrid: fix the output list. Values no longer present in the destination layer palette are
		// removed (only for IntGrid layers: the values are kept intact if the layer is temporarily converted to
		// another type), and offsets are clamped.
		// NOTE: outputs with no value are left intact, so that a half-configured output isn't lost on save.
		for(o in outputs) {
			if( ld.type==IntGrid ) {
				var idx = 0;
				while( idx<o.values.length )
					if( !ld.hasIntGridValue(o.values[idx]) ) {
						App.LOG.add("tidy", 'Removed lost output value ${o.values[idx]} in Rule#$uid');
						o.values.splice(idx,1);
						anyFix = true;
					}
					else
						idx++;
			}

			var clampedX = M.iclamp(o.offsetX, -Const.MAX_RULE_OUTPUT_OFFSET, Const.MAX_RULE_OUTPUT_OFFSET);
			var clampedY = M.iclamp(o.offsetY, -Const.MAX_RULE_OUTPUT_OFFSET, Const.MAX_RULE_OUTPUT_OFFSET);
			if( clampedX!=o.offsetX || clampedY!=o.offsetY ) {
				App.LOG.add("tidy", 'Clamped output offsets in Rule#$uid');
				o.offsetX = clampedX;
				o.offsetY = clampedY;
				anyFix = true;
			}
		}

		// Dual-grid mode: fix invalid state & normalize settings that make no sense in this mode.
		if( dualGrid && (!ld.autoLayerRulesCanBeUsed() || getDualGridValue()<0) ) {
			App.LOG.add("tidy", 'Disabled dual-grid mode of Rule#$uid');
			dualGrid = false;
			anyFix = true;
		}

		if( dualGrid ) {
			if( flipX || flipY ) {
				App.LOG.add("tidy", 'Fixed flips of dual-grid Rule#$uid');
				flipX = false;
				flipY = false;
				anyFix = true;
			}

			if( tileMode!=Single ) {
				App.LOG.add("tidy", 'Fixed tile mode of dual-grid Rule#$uid');
				tileMode = Single;
				anyFix = true;
			}

			if( xModulo!=1 || yModulo!=1 || checker!=None ) {
				App.LOG.add("tidy", 'Fixed modulo/checker of dual-grid Rule#$uid');
				xModulo = 1;
				yModulo = 1;
				checker = None;
				anyFix = true;
			}

			if( xOffset!=0 || yOffset!=0 ) {
				App.LOG.add("tidy", 'Fixed offsets of dual-grid Rule#$uid');
				xOffset = 0;
				yOffset = 0;
				anyFix = true;
			}

			if( tileRandomXMin!=0 || tileRandomXMax!=0 || tileRandomYMin!=0 || tileRandomYMax!=0 ) {
				App.LOG.add("tidy", 'Fixed random offsets of dual-grid Rule#$uid');
				tileRandomXMin = 0;
				tileRandomXMax = 0;
				tileRandomYMin = 0;
				tileRandomYMax = 0;
				anyFix = true;
			}

			if( pivotX!=0 || pivotY!=0 ) {
				App.LOG.add("tidy", 'Fixed pivot of dual-grid Rule#$uid');
				pivotX = 0;
				pivotY = 0;
				anyFix = true;
			}
		}

		return anyFix;
	}

	public function getRandomTileRectIdsForCoord(seed:Int, cx:Int,cy:Int, flips:Int) : Array<Int> {
		if( tileRectsIds.length==0 )
			return [];
		else
			return tileRectsIds[ dn.M.randSeedCoords( uid+seed+flips, cx,cy, tileRectsIds.length ) ];
	}

	public function getRandomOutputValueForCoord(o:RuleOutputDef, oIdx:Int, seed:Int, cx:Int,cy:Int, flips:Int) : Int {
		if( o.values.length==0 )
			return 0;
		else
			// NOTE: the salt keeps the value pick decorrelated from the tile rect pick (which uses the same seed & flips)
			// and from the other outputs of this rule
			return o.values[ dn.M.randSeedCoords( uid+seed+flips+777+oIdx*101, cx,cy, o.values.length ) ];
	}

	public function getXOffsetForCoord(seed:Int, cx:Int,cy:Int, flips:Int) : Int {
		return ( M.hasBit(flips,0)?-1:1 ) * ( tileXOffset + (
			tileRandomXMin==0 && tileRandomXMax==0
				? 0
				: dn.M.randSeedCoords( uid+seed+flips, cx,cy, (tileRandomXMax-tileRandomXMin+1) ) + tileRandomXMin
		));
	}

	public function getYOffsetForCoord(seed:Int, cx:Int,cy:Int, flips:Int) : Int {
		return ( M.hasBit(flips,1)?-1:1 ) * ( tileYOffset + (
			tileRandomYMin==0 && tileRandomYMax==0
				? 0
				: dn.M.randSeedCoords( uid+seed+1, cx,cy, (tileRandomYMax-tileRandomYMin+1) ) + tileRandomYMin
		));
	}

	#end
}