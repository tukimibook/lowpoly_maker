// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'polygon_shape.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PolygonShape {

 String get id; List<String> get vertexIds; Color get fillColor; Color get strokeColor; double get strokeWidth;
/// Create a copy of PolygonShape
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PolygonShapeCopyWith<PolygonShape> get copyWith => _$PolygonShapeCopyWithImpl<PolygonShape>(this as PolygonShape, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PolygonShape&&(identical(other.id, id) || other.id == id)&&const DeepCollectionEquality().equals(other.vertexIds, vertexIds)&&(identical(other.fillColor, fillColor) || other.fillColor == fillColor)&&(identical(other.strokeColor, strokeColor) || other.strokeColor == strokeColor)&&(identical(other.strokeWidth, strokeWidth) || other.strokeWidth == strokeWidth));
}


@override
int get hashCode => Object.hash(runtimeType,id,const DeepCollectionEquality().hash(vertexIds),fillColor,strokeColor,strokeWidth);

@override
String toString() {
  return 'PolygonShape(id: $id, vertexIds: $vertexIds, fillColor: $fillColor, strokeColor: $strokeColor, strokeWidth: $strokeWidth)';
}


}

/// @nodoc
abstract mixin class $PolygonShapeCopyWith<$Res>  {
  factory $PolygonShapeCopyWith(PolygonShape value, $Res Function(PolygonShape) _then) = _$PolygonShapeCopyWithImpl;
@useResult
$Res call({
 String id, List<String> vertexIds, Color fillColor, Color strokeColor, double strokeWidth
});




}
/// @nodoc
class _$PolygonShapeCopyWithImpl<$Res>
    implements $PolygonShapeCopyWith<$Res> {
  _$PolygonShapeCopyWithImpl(this._self, this._then);

  final PolygonShape _self;
  final $Res Function(PolygonShape) _then;

/// Create a copy of PolygonShape
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? vertexIds = null,Object? fillColor = null,Object? strokeColor = null,Object? strokeWidth = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,vertexIds: null == vertexIds ? _self.vertexIds : vertexIds // ignore: cast_nullable_to_non_nullable
as List<String>,fillColor: null == fillColor ? _self.fillColor : fillColor // ignore: cast_nullable_to_non_nullable
as Color,strokeColor: null == strokeColor ? _self.strokeColor : strokeColor // ignore: cast_nullable_to_non_nullable
as Color,strokeWidth: null == strokeWidth ? _self.strokeWidth : strokeWidth // ignore: cast_nullable_to_non_nullable
as double,
  ));
}

}


/// Adds pattern-matching-related methods to [PolygonShape].
extension PolygonShapePatterns on PolygonShape {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PolygonShape value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PolygonShape() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PolygonShape value)  $default,){
final _that = this;
switch (_that) {
case _PolygonShape():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PolygonShape value)?  $default,){
final _that = this;
switch (_that) {
case _PolygonShape() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  List<String> vertexIds,  Color fillColor,  Color strokeColor,  double strokeWidth)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PolygonShape() when $default != null:
return $default(_that.id,_that.vertexIds,_that.fillColor,_that.strokeColor,_that.strokeWidth);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  List<String> vertexIds,  Color fillColor,  Color strokeColor,  double strokeWidth)  $default,) {final _that = this;
switch (_that) {
case _PolygonShape():
return $default(_that.id,_that.vertexIds,_that.fillColor,_that.strokeColor,_that.strokeWidth);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  List<String> vertexIds,  Color fillColor,  Color strokeColor,  double strokeWidth)?  $default,) {final _that = this;
switch (_that) {
case _PolygonShape() when $default != null:
return $default(_that.id,_that.vertexIds,_that.fillColor,_that.strokeColor,_that.strokeWidth);case _:
  return null;

}
}

}

/// @nodoc


class _PolygonShape implements PolygonShape {
  const _PolygonShape({required this.id, required final  List<String> vertexIds, required this.fillColor, required this.strokeColor, required this.strokeWidth}): _vertexIds = vertexIds;
  

@override final  String id;
 final  List<String> _vertexIds;
@override List<String> get vertexIds {
  if (_vertexIds is EqualUnmodifiableListView) return _vertexIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_vertexIds);
}

@override final  Color fillColor;
@override final  Color strokeColor;
@override final  double strokeWidth;

/// Create a copy of PolygonShape
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PolygonShapeCopyWith<_PolygonShape> get copyWith => __$PolygonShapeCopyWithImpl<_PolygonShape>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PolygonShape&&(identical(other.id, id) || other.id == id)&&const DeepCollectionEquality().equals(other._vertexIds, _vertexIds)&&(identical(other.fillColor, fillColor) || other.fillColor == fillColor)&&(identical(other.strokeColor, strokeColor) || other.strokeColor == strokeColor)&&(identical(other.strokeWidth, strokeWidth) || other.strokeWidth == strokeWidth));
}


@override
int get hashCode => Object.hash(runtimeType,id,const DeepCollectionEquality().hash(_vertexIds),fillColor,strokeColor,strokeWidth);

@override
String toString() {
  return 'PolygonShape(id: $id, vertexIds: $vertexIds, fillColor: $fillColor, strokeColor: $strokeColor, strokeWidth: $strokeWidth)';
}


}

/// @nodoc
abstract mixin class _$PolygonShapeCopyWith<$Res> implements $PolygonShapeCopyWith<$Res> {
  factory _$PolygonShapeCopyWith(_PolygonShape value, $Res Function(_PolygonShape) _then) = __$PolygonShapeCopyWithImpl;
@override @useResult
$Res call({
 String id, List<String> vertexIds, Color fillColor, Color strokeColor, double strokeWidth
});




}
/// @nodoc
class __$PolygonShapeCopyWithImpl<$Res>
    implements _$PolygonShapeCopyWith<$Res> {
  __$PolygonShapeCopyWithImpl(this._self, this._then);

  final _PolygonShape _self;
  final $Res Function(_PolygonShape) _then;

/// Create a copy of PolygonShape
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? vertexIds = null,Object? fillColor = null,Object? strokeColor = null,Object? strokeWidth = null,}) {
  return _then(_PolygonShape(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,vertexIds: null == vertexIds ? _self._vertexIds : vertexIds // ignore: cast_nullable_to_non_nullable
as List<String>,fillColor: null == fillColor ? _self.fillColor : fillColor // ignore: cast_nullable_to_non_nullable
as Color,strokeColor: null == strokeColor ? _self.strokeColor : strokeColor // ignore: cast_nullable_to_non_nullable
as Color,strokeWidth: null == strokeWidth ? _self.strokeWidth : strokeWidth // ignore: cast_nullable_to_non_nullable
as double,
  ));
}


}

// dart format on
