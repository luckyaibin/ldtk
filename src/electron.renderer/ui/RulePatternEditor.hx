package ui;

class RulePatternEditor {
	public var jRoot : js.jquery.JQuery;

	var rule : data.def.AutoLayerRuleDef;
	var sourceDef : data.def.LayerDef;
	var layerDef : data.def.LayerDef;
	var previewMode : Bool;
	var explainCell : Null< (desc:Null<String>)->Void >;
	var getSelectedValue: Null< Void->Int >;
	var onChange: Null< Void->Void >;

	var drawButton = -1;
	var valueAtStartPoint : Null<Int> = null; // value when clicking starts

	public function new(
		rule: data.def.AutoLayerRuleDef,
		sourceDef: data.def.LayerDef,
		layerDef: data.def.LayerDef,
		previewMode=false,
		?explainCell: (desc:Null<String>)->Void,
		?getSelectedValue: Void->Int,
		?onChange: Void->Void
	) {
		this.rule = rule;
		this.sourceDef = sourceDef;
		this.layerDef = layerDef;
		this.previewMode = previewMode;
		this.explainCell = explainCell;
		this.getSelectedValue = getSelectedValue;
		this.onChange = onChange;

		valueAtStartPoint = null;
		jRoot = new J('<div/>');

		render();
	}


	inline function isEditable() return onChange!=null;


	function render() {
		// Init root
		jRoot.empty().off();
		jRoot.removeClass();
		jRoot.addClass("autoPatternGrid");
		jRoot.addClass("size-"+rule.size);

		if( isEditable() )
			jRoot.addClass("editable");

		if( previewMode )
			jRoot.addClass("preview");

		if( rule.dualGrid )
			jRoot.addClass("dualgrid");

		// Add a rollover tip
		function addExplain(jTarget:js.jquery.JQuery, desc:String) {
			if( explainCell==null )
				return;

			jTarget
				.mouseover( function(_) {
					explainCell(desc);
				})
				.mouseout( function(_) {
					explainCell(null);
				});
		}

		var buttonDown = -1;

		for(cy in 0...rule.size)
		for(cx in 0...rule.size) {
			var coordId = cx+cy*rule.size;
			var isCenter = cx==Std.int(rule.size/2) && cy==Std.int(rule.size/2);

			// Cell wrapper
			var jCell = new J('<div class="cell"/>');
			jCell.appendTo(jRoot);
			if( isEditable() )
				jCell.addClass("editable");

			// Dual-grid mode: only the center cell (the "terrain" value) is used
			var isDualGridIgnoredCell = rule.dualGrid && !isCenter;
			if( isDualGridIgnoredCell ) {
				jCell.addClass("disabled");
				addExplain(jCell, 'This cell is ignored.\nIn dual-grid mode, only the center value matters: it defines the terrain rendered at each grid corner, using the 4 cells around that corner.');
			}

			// Center guide
			if( isCenter && !layerDef.isDerived() ) { // Derived IntGrid layers don't render tiles: keep the center cell as a regular pattern cell
				switch rule.tileMode {
					case Single:
						jCell.addClass("center");

					case Stamp:
						var jStampPreview = new J('<div class="stampPreview"/>');
						jStampPreview.appendTo(jCell);
						var previewWid = 32;
						var previewHei = 32;
						if( rule.tileRectsIds.length>0 && rule.tileRectsIds[0].length>1 ) {
							var td = Editor.ME.curLayerInstance.getTilesetDef();
							if( td!=null ) {
								var bounds = td.getTileGroupBounds(rule.tileRectsIds[0]);
								if( bounds.wid>1 )
									previewWid = Std.int( previewWid * 1.9 );
								if( bounds.hei>1 )
									previewHei = Std.int( previewHei * 1.9 );
							}
						}
						jStampPreview.css("width", previewWid + "px");
						jStampPreview.css("height", previewHei + "px");
						jStampPreview.css("left", ( rule.pivotX * (32-previewWid) ) + "px");
						jStampPreview.css("top", ( rule.pivotY * (32-previewHei) ) + "px");
				}

				// Render actual Tile in context
				if( previewMode ) {
					var td = Editor.ME.curLayerInstance.getTilesetDef();
					if( td!=null ) {
						var previewTid : Null<Int> = null;
						var hasMultipleTids = false;
						if( rule.dualGrid ) {
							// Dual-grid: preview the last filled mask slot's tile (usually the "full block" mask 15)
							for(mask in 0...rule.tileRectsIds.length)
								if( rule.tileRectsIds[mask].length>0 ) {
									previewTid = rule.tileRectsIds[mask][0];
									hasMultipleTids = rule.tileRectsIds[mask].length>1;
								}
						}
						else if( rule.tileRectsIds.length>0 ) {
							previewTid = rule.tileRectsIds[0][0];
							hasMultipleTids = rule.tileRectsIds.length>1;
						}
						var jTile = td.createCanvasFromTileId(previewTid, 32);
						jCell.append(jTile);
						if( hasMultipleTids )
							jTile.addClass("multi");
					}
				}
			}

			// Cell value (color + tile)
			if( !isDualGridIgnoredCell && (!isCenter || !previewMode || layerDef.isDerived()) ) {
				var ruleValue = rule.getPattern(cx,cy);
				if( ruleValue!=0 ) {
					var intGridVal = M.iabs(ruleValue);
					if( ruleValue>0 ) {
						// Required value
						if( intGridVal == Const.AUTO_LAYER_ANYTHING ) {
							jCell.addClass("anything");
							addExplain(jCell, 'This cell should contain any IntGrid value to match.');
						}
						else if( intGridVal>999 ) {
							var groupUid = sourceDef.resolveIntGridGroupUidFromRuleValue(intGridVal);
							var color = sourceDef.getIntGridGroupColor(groupUid);
							jCell.addClass("group");
							if( color!=null ) {
								jCell.css("background-color", color.toCssRgba(0.9));
								jCell.css("outline-color", color.toWhite(0.6).toHex());
							}
							var name = sourceDef.getIntGridGroupDisplayName(groupUid);
							addExplain(jCell, 'This cell should contain any IntGrid value from the group $name to match.');
						}
						else if( sourceDef.hasIntGridValue(intGridVal) ) {
							jCell.css("background-color", C.intToHex( sourceDef.getIntGridValueDef(intGridVal).color ) );
							var iv = sourceDef.getIntGridValueDef(intGridVal);
							if( iv.tile!=null )
								jCell.prepend( sourceDef._project.resolveTileRectAsHtmlImg(iv.tile).addClass("valueIcon") );
							addExplain(jCell, 'This cell should contain "${sourceDef.getIntGridValueDisplayName(intGridVal)}" to match.');
						}
						else
							jCell.addClass("unknown");
					}
					else {
						// Forbidden value
						jCell.addClass("not");
						var icon = intGridVal!=Const.AUTO_LAYER_ANYTHING ? "cross" : "nothing";
						jCell.append('<span class="cellIcon $icon"></span>');

						if( intGridVal == Const.AUTO_LAYER_ANYTHING ) {
							jCell.addClass("anything");
							addExplain(jCell, 'This cell should NOT contain any IntGrid value to match.');
						}
						else if( intGridVal>999 ) {
							var groupUid = sourceDef.resolveIntGridGroupUidFromRuleValue(intGridVal);
							var color = sourceDef.getIntGridGroupColor(groupUid);
							jCell.addClass("group");
							if( color!=null ) {
								jCell.css("background-color", color.toCssRgba(0.9));
								jCell.css("outline-color", color.toWhite(0.6).toHex());
							}
							var name = sourceDef.getIntGridGroupDisplayName(groupUid);
							addExplain(jCell, 'This cell should NOT contain any IntGrid value from the group $name to match.');
						}
						else if( sourceDef.hasIntGridValue(intGridVal) ) {
							jCell.css("background-color", C.intToHex( sourceDef.getIntGridValueDef(intGridVal).color ) );
							var iv = sourceDef.getIntGridValueDef(intGridVal);
							if( iv.tile!=null )
								jCell.prepend( sourceDef._project.resolveTileRectAsHtmlImg(iv.tile).addClass("valueIcon") );
							addExplain(jCell, 'This cell should NOT contain "${sourceDef.getIntGridValueDisplayName(intGridVal)}" to match.');
						}
						else
							jCell.addClass("error");
					}
				}
				else {
					// "Anything" value
					addExplain(jCell, 'This cell content doesn\'t matter.');
					jCell.addClass("empty");
				}
			}

			// Edit grid value
			if( isEditable() && !isDualGridIgnoredCell ) {

				var anyChange = false;
				function draw() {

					var v = rule.getPattern(cx,cy);
					switch drawButton {
						case 0:
							// Require value
							if( valueAtStartPoint>=0 )
								rule.setPattern(cx,cy, getSelectedValue());
							else if( v<0 )
								rule.setPattern(cx,cy, 0);

						case 2:
							// Forbid value
							if( valueAtStartPoint==0 )
								rule.setPattern(cx,cy, -getSelectedValue());
							else
								rule.setPattern(cx,cy, 0);

						case 1:
							// Clear
							rule.setPattern(cx,cy,0);

						case _:
					}

					// Refresh
					if( v!=rule.getPattern(cx,cy) ) {
						anyChange = true;
						rule.updateUsedValues();
						render();
					}

				}

				jCell.mousedown( (ev:js.jquery.Event)->{
					valueAtStartPoint = rule.getPattern(cx,cy);
					drawButton = ev.button;
					App.ME.jBody.on("mouseup.rulePattern", (_)->{
						drawButton = -1;
						App.ME.jBody.off("mouseup.rulePattern");
						if( anyChange )
							onChange();
					});
					draw();
				});

				jCell.mousemove( function(ev) {
					if( drawButton>=0 )
						draw();
				});
			}
		}

		return jRoot;
	}
}