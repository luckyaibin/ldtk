package ui.modal.dialog;

import data.DataTypes;

class RuleEditor extends ui.modal.Dialog {
	var curValue = -1;
	var layerDef : data.def.LayerDef;
	var sourceDef : data.def.LayerDef;
	var rule : data.def.AutoLayerRuleDef;
	var guidedMode = false;
	var hasAnyChange = false;

	public function new(layerDef:data.def.LayerDef, rule:data.def.AutoLayerRuleDef) {
		super("ruleEditor");

		if( rule.size<Const.MAX_AUTO_PATTERN_SIZE )
			rule.resize(Const.MAX_AUTO_PATTERN_SIZE);

		setTransparentMask();
		this.layerDef = layerDef;
		this.rule = rule;
		sourceDef = layerDef.type==IntGrid && !layerDef.isDerived() ? layerDef : project.defs.getLayerDef( layerDef.autoSourceLayerDefUid );
		if( sourceDef==null )
			sourceDef = layerDef; // Safety fallback (eg. missing source layer)

		// Smart pick current IntGrid value
		curValue = -1;
		var counts = new Map();
		var best = -1;
		for(cy in 0...rule.size)
		for(cx in 0...rule.size) {
			var v = M.iabs( rule.getPattern(cx,cy) );
			if( v==0 || v==Const.AUTO_LAYER_ANYTHING )
				continue;

			if( !counts.exists(v) )
				counts.set(v,1);
			else
				counts.set(v,counts.get(v)+1);

			if( best<0 || counts.get(best)<counts.get(v) )
				best = v;
		}
		curValue = best;

		// Default current value
		if( curValue<0 )
			for(iv in sourceDef.getAllIntGridValues()) {
				curValue = iv.value;
				break;
			}
		if( curValue==-1 )
			curValue = Const.AUTO_LAYER_ANYTHING;

		renderAll();
	}

	override function onGlobalEvent(e:GlobalEvent) {
		super.onGlobalEvent(e);
		switch(e) {
			case LayerRuleChanged(rule):

			case _:
		}
	}

	function enableGuidedMode() {
		guidedMode = true;
		jContent.addClass("guided");
		jContent.find(".disableTip").removeClass("disableTip");
		jContent.find(".explain").show();
	}


	override function close() {
		rule.trim();
		rule.updateUsedValues();

		super.close();

		if( rule.isEmpty() ) {
			// Kill empty
			for(rg in layerDef.autoRuleGroups)
				rg.rules.remove(rule);
			editor.ge.emit( LayerRuleRemoved(rule, false) );
		}
		else {
			rule.tidy(layerDef);
			if( hasAnyChange ) {
				editor.ge.emit( LayerRuleChanged(rule) );
				N.msg("Rule updated");
			}
		}
	}


	function onAnyRuleChange() {
		hasAnyChange = true;
		// editor.ge.emit( LayerRuleChanged(rule) );
	}


	/** Toggle the dual-grid mode. Only meaningful on layers rendering tiles (not derived ones). **/
	function setDualGrid(on:Bool) {
		rule.dualGrid = on;
		if( on ) {
			// Only the center value is used: clear all the other pattern cells
			var center = Std.int(rule.size*0.5);
			for(cy in 0...rule.size)
			for(cx in 0...rule.size)
				if( cx!=center || cy!=center )
					rule.setPattern(cx,cy,0);

			// Default the center value (the "terrain") to the first IntGrid value of the source layer
			if( rule.getDualGridValue()<0 )
				for(iv in sourceDef.getAllIntGridValues()) {
					rule.setPattern(center, center, iv.value);
					break;
				}
			rule.updateUsedValues();

			// Settings that don't make sense in this mode
			rule.flipX = false;
			rule.flipY = false;
			rule.tileMode = Single;
			rule.xModulo = 1;
			rule.yModulo = 1;
			rule.checker = ldtk.Json.AutoLayerRuleCheckerMode.None;
			rule.xOffset = 0;
			rule.yOffset = 0;
			rule.tileRandomXMin = 0;
			rule.tileRandomXMax = 0;
			rule.tileRandomYMin = 0;
			rule.tileRandomYMax = 0;
			rule.pivotX = 0;
			rule.pivotY = 0;

			// Default offset: center the tile on the corner = half a TILESET TILE.
			// Standard dual-grid "windmill" tiles span 2x2 logical cells, so this is usually one full cell.
			if( rule.tileXOffset==0 && rule.tileYOffset==0 ) {
				var td = project.defs.getTilesetDef(layerDef.tilesetDefUid);
				var tileSize = td!=null ? td.tileGridSize : layerDef.gridSize;
				rule.tileXOffset = -Std.int(tileSize*0.5);
				rule.tileYOffset = -Std.int(tileSize*0.5);
			}
		}

		onAnyRuleChange();
		renderAll();
	}


	/**
	Dual-grid mode: one tile per 0-15 mask of the 4 cells around a grid corner (bit 1=NW, 2=NE, 4=SW, 8=SE).
	The tile for each mask is picked here.
	**/
	function updateDualGridSettings() {
		var jSettings = jContent.find(".dualGridSettings");
		jSettings.off();
		var jSlots = jSettings.find(".maskSlots").empty();

		var td = project.defs.getTilesetDef(layerDef.tilesetDefUid);
		if( td==null ) {
			jSlots.append('<div class="error">Invalid tileset</div>');
			return;
		}

		for(mask in 0...Const.DUAL_GRID_MASK_COUNT) {
			var tids = mask<rule.tileRectsIds.length ? rule.tileRectsIds[mask] : [];

			var jSlot = new J('<div class="maskSlot"/>');
			jSlot.appendTo(jSlots);

			// Quadrant diagram: which of the 4 corner cells are covered by this mask
			var jDiag = new J('<div class="diagram"/>');
			jDiag.appendTo(jSlot);
			for(bit in 0...4) {
				var jQ = new J('<span class="q"/>');
				if( M.hasBit(mask,bit) )
					jQ.addClass("on");
				jQ.appendTo(jDiag);
			}

			// Tile (if any)
			if( tids.length>0 )
				jSlot.append( td.createTileHtmlImageFromTileId(tids[0]) );
			else
				jSlot.append('<span class="noTile">-</span>');

			var m = mask;
			Tip.attach(jSlot, 'Mask $m\nLeft click: pick tile(s) for this mask\nRight click: clear');
			jSlot.mousedown( (ev:js.jquery.Event)->{
				switch ev.button {
					case 0:
						JsTools.openTilePickerModal(
							Editor.ME.curLayerInstance.getTilesetUid(),
							MultipleIndividuals,
							tids.copy(),
							false,
							function(picked) {
								if( picked.length>0 ) {
									while( rule.tileRectsIds.length<=m )
										rule.tileRectsIds.push([]);
									rule.tileRectsIds[m] = picked.copy();
									onAnyRuleChange();
									updateDualGridSettings();
								}
							}
						);

					case 1,2:
						if( tids.length>0 ) {
							rule.tileRectsIds[m] = [];
							onAnyRuleChange();
							updateDualGridSettings();
						}
				}
			});
		}

		// Fill all 16 masks from a 4x4 tileset block
		jSettings.find(".fillFromTileset").click( _->{
			JsTools.openTilePickerModal(
				Editor.ME.curLayerInstance.getTilesetUid(),
				TileRectAndClose,
				[],
				false,
				function(picked) {
					if( picked.length==0 )
						return;

					// In a standard dual-grid tileset, the 16 tiles are laid out as x=NW+NE*2, y=SW+SE*2,
					// ie. the mask of the tile at column bx, row by is bx+by*4
					var rect = td.getTileRectFromTileIds(picked);
					var ox = td.xToCx(rect.x), oy = td.yToCy(rect.y);
					var slots = [];
					for(i in 0...Const.DUAL_GRID_MASK_COUNT)
						slots.push([]);
					var cnt = 0;
					for(tid in picked) {
						var bx = td.getTileCx(tid)-ox;
						var by = td.getTileCy(tid)-oy;
						if( bx>=0 && bx<4 && by>=0 && by<4 && slots[bx+by*4].length==0 ) {
							slots[bx+by*4] = [tid];
							cnt++;
						}
					}
					if( picked.length!=16 || cnt<16 ) {
						N.error("Please select a full 4x4 tileset block");
						return;
					}
					rule.tileRectsIds = slots;
					onAnyRuleChange();
					updateDualGridSettings();
				}
			);
		});

		JsTools.parseComponents(jSettings);
	}


	function updateTileSettings() {
		if( layerDef.isDerived() )
			return; // Derived IntGrid layers don't render tiles

		var jTilesSettings = jContent.find(".tileSettings");
		jTilesSettings.off();

		// Dual-grid toggle
		var jChk = jContent.find(".dualGridToggle input[name=dualGrid]");
		jChk.off().prop("checked", rule.dualGrid);
		jChk.change( function(_) setDualGrid( jChk.prop("checked") ) );

		if( rule.dualGrid ) {
			updateDualGridSettings();
			JsTools.parseComponents(jTilesSettings);
			return;
		}

		// Tile mode
		var jModeSelect = jContent.find("select[name=tileMode]");
		jModeSelect.empty();
		var i = new form.input.EnumSelect(
			jModeSelect,
			ldtk.Json.AutoLayerRuleTileMode,
			()->rule.tileMode,
			(v)->rule.tileMode = v,
			(v)->switch v {
				case Single: Lang.t._("Individual tiles");
				case Stamp: Lang.t._("Rectangles of tiles");
			}
		);
		i.onChange = function() {
			onAnyRuleChange();
			rule.tileRectsIds = [];
			updateTileSettings();
		}

		// Tile(s)
		var jTileRects = jTilesSettings.find(">.tileRects").empty();
		function _pickTiles(rectIdx:Int) {
			var pickerTids = rectIdx<0 || rule.tileRectsIds.length==0 ? [] : switch rule.tileMode {
				case Single: rule.tileRectsIds.map( tids->tids[0] );
				case Stamp: rule.tileRectsIds[rectIdx];
			}
			JsTools.openTilePickerModal(
				Editor.ME.curLayerInstance.getTilesetUid(),
				rule.tileMode==Single ? MultipleIndividuals : TileRectAndClose,
				pickerTids,
				false,
				function(tids) {
					if( tids.length>0 ) {
						switch rule.tileMode {
							case Single:
								rule.tileRectsIds = tids.map( tid->[tid] );

							case Stamp:
								if( rectIdx<0 )
									rule.tileRectsIds.push( tids.copy() );
								else
									rule.tileRectsIds[rectIdx] = tids.copy();
						}
					}
					updateTileSettings();
					onAnyRuleChange();
				}
			);
		}
		var jAllTiles = new J('<div class="allTiles"/>');
		jAllTiles.appendTo(jTileRects);
		var td = project.defs.getTilesetDef(layerDef.tilesetDefUid);
		if( td==null )
			jAllTiles.append('<div class="error">Invalid tileset</div>');
		else {
			switch rule.tileMode {
				case Single:
					for(rectIds in rule.tileRectsIds)
						jAllTiles.append( td.createTileHtmlImageFromTileId(rectIds[0]) );
					jAllTiles.addClass("clickable");
					jAllTiles.click( _->_pickTiles(0) );

				case Stamp:
					var rectIdx = 0;
					for(rectIds in rule.tileRectsIds) {
						var rect = td.getTileRectFromTileIds(rectIds);
						var jImg = td.createTileHtmlImageFromRect(rect);
						jImg.addClass("clickable");
						Tip.attach(jImg, "Left click to change\nRight click to remove");
						var i = rectIdx;
						jImg.mousedown( (ev:js.jquery.Event)->{
							switch ev.button {
								case 0:
									_pickTiles(i);

								case 1,2:
									rule.tileRectsIds.splice(i,1);
									onAnyRuleChange();
									updateTileSettings();
							}
						});
						jAllTiles.append( jImg );
						rectIdx++;
					}
					if( rule.tileRectsIds.length>0 ) {
						var jAdd = new J('<button> <span class="icon add"></span> </button>');
						jAdd.appendTo(jAllTiles);
						jAdd.click( _->_pickTiles(-1) );
					}
					else {
						jAllTiles.addClass("clickable");
						jAllTiles.click( _->_pickTiles(0) );
					}
			}
		}


		// Pivot (optional)
		var jTileOptions = jTilesSettings.find(">.options").empty();
		switch rule.tileMode {
			case Single:
			case Stamp:
				var jPivot = JsTools.createPivotEditor(rule.pivotX, rule.pivotY, (xr,yr)->{
					rule.pivotX = xr;
					rule.pivotY = yr;
					onAnyRuleChange();
					renderAll();
				});
				jTileOptions.append(jPivot);
		}

		JsTools.parseComponents(jTilesSettings);
	}



	/**
		Derived IntGrid layers: a rule can write several cells at once. Every "output" below picks which
		IntGrid value(s) of THIS layer it writes (if several, one is randomly picked using the layer seed for
		each matched cell) and the cell offset of its destination.
	**/
	function updateOutputSettings() {
		var jOutput = jContent.find(".outputSettings");
		jOutput.off();

		var allValues = layerDef.getAllIntGridValues();
		var jList = jOutput.find(">.outputList").empty();

		if( allValues.length==0 )
			jList.append('<div class="error">This layer has no IntGrid values: add some in the layer settings!</div>');

		var oIdx = 0;
		while( oIdx<rule.outputs.length ) {
			var idx = oIdx;
			var o = rule.outputs[oIdx];
			oIdx++;

			var jEntry = new J('<div class="outputEntry"/>');
			jEntry.appendTo(jList);

			// Value(s) written by this output (from the derived layer's own palette)
			var jValues = new J('<div class="values"/>');
			jValues.appendTo(jEntry);
			for(iv in allValues) {
				var jVal = new J('<div class="outputValue"/>');
				jVal.appendTo(jValues);
				jVal.css("background-color", C.intToHex(iv.color));
				jVal.append( JsTools.createIntGridValue(project, iv, false) );
				jVal.append('<span class="name">${iv.identifier!=null ? iv.identifier : Std.string(iv.value)}</span>');
				jVal.find(".name").css("color", C.intToHex( C.autoContrast(iv.color) ) );

				if( o.values.indexOf(iv.value)>=0 )
					jVal.addClass("active");

				var v = iv.value;
				Tip.attach(jVal, "Click to toggle this output value");
				jVal.click(_->{
					if( o.values.indexOf(v)>=0 )
						o.values.remove(v);
					else
						o.values.push(v);
					onAnyRuleChange();
					updateOutputSettings();
				});
			}
			if( o.values.length==0 )
				jValues.append('<em class="empty">No value!</em>');

			// Destination cell of this output
			var jOffsets = new J('<div class="offsets"/>');
			jOffsets.appendTo(jEntry);
			jOffsets.append('<span>Write in cell offset:</span>');
			jOffsets.append('<span>X=</span>');
			var iX = new form.input.IntInput(
				new J('<input type="text" class="small" name="outputOffsetX"/>').appendTo(jOffsets),
				()->o.offsetX,
				(v)->o.offsetX = v
			);
			iX.setBounds(-Const.MAX_RULE_OUTPUT_OFFSET, Const.MAX_RULE_OUTPUT_OFFSET);
			iX.onChange = ()->onAnyRuleChange();
			jOffsets.append('<span>Y=</span>');
			var iY = new form.input.IntInput(
				new J('<input type="text" class="small" name="outputOffsetY"/>').appendTo(jOffsets),
				()->o.offsetY,
				(v)->o.offsetY = v
			);
			iY.setBounds(-Const.MAX_RULE_OUTPUT_OFFSET, Const.MAX_RULE_OUTPUT_OFFSET);
			iY.onChange = ()->onAnyRuleChange();
			jOffsets.append('<span>cells</span>');

			// Remove this output
			var jDel = new J('<button class="delete"><span class="icon delete"></span></button>');
			jDel.appendTo(jEntry);
			Tip.attach(jDel, "Remove this output");
			jDel.click(_->{
				rule.outputs.splice(idx,1);
				onAnyRuleChange();
				updateOutputSettings();
			});
		}

		// Add a new (empty) output
		var jAdd = jOutput.find(">.addOutput").off();
		Tip.attach(jAdd, "Add another cell to write for each match");
		jAdd.click(_->{
			rule.outputs.push( new data.def.RuleOutputDef() );
			onAnyRuleChange();
			updateOutputSettings();
		});

		JsTools.parseComponents(jOutput);
	}


	function updateValuePalette() {
		var jValuePalette = jContent.find(">.pattern .valuePalette>ul").empty();

		// Values view mode
		var stateId = settings.makeStateId(RuleValuesColumns, layerDef.uid);
		var columns = settings.getUiStateInt(stateId, project, 5);
		JsTools.removeClassReg(jValuePalette, ~/col-[0-9]+/g);
		jValuePalette.addClass("col-"+columns);

		// View select
		var jMode = jContent.find(".displayMode");
		jMode.off().click(_->{
			var m = new ContextMenu(jMode);
			m.addAction({
				label:L.t._("List"),
				iconId: "listView",
				cb: ()->{
					settings.deleteUiState(stateId, project);
					updateValuePalette();
				}
			});
			for(n in [2,3,4,5,6,7,8,9,10]) {
				m.addAction({
					label:L.t._("::n:: columns", {n:n}),
					iconId: "gridView",
					cb: ()->{
						settings.setUiStateInt(stateId, n, project);
						updateValuePalette();
					}
				});
			}
		});

		// Groups
		for(g in sourceDef.getGroupedIntGridValues()) {
			if( g.all.length==0 )
				continue;

			var groupValue = sourceDef.getRuleValueFromGroupUid(g.groupUid);

			var jHeader = new J('<li class="title"/>');
			jHeader.append('<span class="icon folderClose"/>');
			if( sourceDef.hasIntGridGroups() ) {
				jHeader.appendTo(jValuePalette);
				jHeader.append('<span class="name">${g.displayName}</span>');

				jHeader.click(_->{
					curValue = groupValue;
					updateValuePalette();
				});
			}

			var jSubList = new J('<li class="subList"> <ul class="groupValues"></ul> </li>');
			jSubList.appendTo(jValuePalette);

			if( g.color!=null ) {
				var alpha = curValue==groupValue ? 1 : 0.4;
				jHeader.css("background-color", g.color.toCssRgba(0.8*alpha));
				jSubList.css("background-color", g.color.toCssRgba(0.5*alpha));
			}

			if( curValue==groupValue )
				jHeader.add(jSubList).addClass("active");

			// Individual values
			jSubList = jSubList.find("ul");
			for(v in g.all) {
				var jVal = new J('<li class="value"/>');
				jVal.appendTo(jSubList);
				jVal.css("background-color", C.intToHex(v.color));
				jVal.append( JsTools.createIntGridValue(project, v, false) );
				jVal.append('<span class="name">${v.identifier!=null ? v.identifier : Std.string(v.value)}</span>');
				jVal.find(".name").css("color", C.intToHex( C.autoContrast(v.color) ) );

				if( curValue==v.value )
					jVal.addClass("active");

				var id = v.value;
				jVal.click( function(ev) {
					curValue = id;
					updateValuePalette();
				});
			}
		}

		// "Anything" value
		var jVal = new J('<li/>');
		jVal.appendTo(jValuePalette);
		jVal.addClass("any");
		jVal.append('<span class="value"></span>');
		var label = '"Any value" / "No value"';
		jVal.append('<span class="name">$label</span>');
		if( curValue==Const.AUTO_LAYER_ANYTHING )
			jVal.addClass("active");
		jVal.click( function(ev) {
			curValue = Const.AUTO_LAYER_ANYTHING;
			onAnyRuleChange();
			updateValuePalette();
		});
	}


	function renderAll() {

		loadTemplate("ruleEditor");

		// Derived IntGrid layers: swap tile settings for output values & offsets
		if( layerDef.isDerived() )
			jContent.addClass("derived");
		else
			jContent.removeClass("derived");

		// Dual-grid mode: swap the regular tile UI for the 16 mask slots
		if( rule.dualGrid )
			jContent.addClass("dualgrid");
		else
			jContent.removeClass("dualgrid");

		jContent.find("[data-title],[title]").addClass("disableTip"); // removed on guided mode

		// Mini explanation tip
		var jExplain = jContent.find(".explain").hide();

		// Guided mode button
		jContent.find("button.guide").click( (_)->{
			enableGuidedMode();
		} );
		jContent.find(".debugInfos").text('#${rule.uid}');

		updateTileSettings();

		if( layerDef.isDerived() )
			updateOutputSettings();

		// Pattern grid editor
		var patternEditor = new RulePatternEditor(
			rule, sourceDef, layerDef,
			(str:String)->{
				if( str==null )
					jExplain.empty();
				else {
					if( str.indexOf("\\n")>=0 )
						str = "<p>" + str.split("\\n").join("</p><p>") + "</p>";
					jExplain.html(str);
				}
			},
			()->curValue,
			()->onAnyRuleChange()
		);
		jContent.find(">.pattern .editor .grid").empty().append( patternEditor.jRoot );

		// Out-of-bounds policy
		var jOutOfBounds = jContent.find("#outOfBoundsValue");
		JsTools.createOutOfBoundsRulePolicy(jOutOfBounds, sourceDef, rule.outOfBoundsValue, (v)->{
			rule.outOfBoundsValue = v;
			onAnyRuleChange();
			renderAll();
		});

		// Finalize
		updateValuePalette();
		if( guidedMode )
			enableGuidedMode();

		JsTools.parseComponents(jContent);
	}

}