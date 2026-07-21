// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'artwork.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Artwork {

 String get id; String get title; Map<String, Vertex> get vertices; List<PolygonShape> get polygons; List<String> get draftVertexIds;
/// Create a copy of Artwork
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ArtworkCopyWith<Artwork> get copyWith => _$ArtworkCopyWithImpl<Artwork>(this as Artwork, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Artwork&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&const DeepCollectionEquality().equals(other.vertices, vertices)&&const DeepCollectionEquality().equals(other.polygons, polygons)&&const DeepCollectionEquality().equals(other.draftVertexIds, draftVertexIds));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,const DeepCollectionEquality().hash(vertices),const DeepCollectionEquality().hash(polygons),const DeepCollectionEquality().hash(draftVertexIds));

@override
String toString() {
  return 'Artwork(id: $id, title: $title, vertices: $vertices, polygons: $polygons, draftVertexIds: $draftVertexIds)';
}


}

/// @nodoc
abstract mixin class $ArtworkCopyWith<$Res>  {
  factory $ArtworkCopyWith(Artwork value, $Res Function(Artwork) _then) = _$ArtworkCopyWithImpl;
@useResult
$Res call({
 String id, String title, Map<String, Vertex> vertices, List<PolygonShape> polygons, List<String> draftVertexIds
});




}
/// @nodoc
class _$ArtworkCopyWithImpl<$Res>
    implements $ArtworkCopyWith<$Res> {
  _$ArtworkCopyWithImpl(this._self, this._then);

  final Artwork _self;
  final $Res Function(Artwork) _then;

/// Create a copy of Artwork
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? vertices = null,Object? polygons = null,Object? draftVertexIds = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,vertices: null == vertices ? _self.vertices : vertices // ignore: cast_nullable_to_non_nullable
as Map<String, Vertex>,polygons: null == polygons ? _self.polygons : polygons // ignore: cast_nullable_to_non_nullable
as List<PolygonShape>,draftVertexIds: null == draftVertexIds ? _self.draftVertexIds : draftVertexIds // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [Artwork].
extension ArtworkPatterns on Artwork {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Artwork value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Artwork() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Artwork value)  $default,){
final _that = this;
switch (_that) {
case _Artwork():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Artwork value)?  $default,){
final _that = this;
switch (_that) {
case _Artwork() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  Map<String, Vertex> vertices,  List<PolygonShape> polygons,  List<String> draftVertexIds)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Artwork() when $default != null:
return $default(_that.id,_that.title,_that.vertices,_that.polygons,_that.draftVertexIds);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  Map<String, Vertex> vertices,  List<PolygonShape> polygons,  List<String> draftVertexIds)  $default,) {final _that = this;
switch (_that) {
case _Artwork():
return $default(_that.id,_that.title,_that.vertices,_that.polygons,_that.draftVertexIds);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  Map<String, Vertex> vertices,  List<PolygonShape> polygons,  List<String> draftVertexIds)?  $default,) {final _that = this;
switch (_that) {
case _Artwork() when $default != null:
return $default(_that.id,_that.title,_that.vertices,_that.polygons,_that.draftVertexIds);case _:
  return null;

}
}

}

/// @nodoc


class _Artwork implements Artwork {
  const _Artwork({required this.id, required this.title, final  Map<String, Vertex> vertices = const <String, Vertex>{}, final  List<PolygonShape> polygons = const <PolygonShape>[], final  List<String> draftVertexIds = const <String>[]}): _vertices = vertices,_polygons = polygons,_draftVertexIds = draftVertexIds;
  

@override final  String id;
@override final  String title;
 final  Map<String, Vertex> _vertices;
@override@JsonKey() Map<String, Vertex> get vertices {
  if (_vertices is EqualUnmodifiableMapView) return _vertices;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_vertices);
}

 final  List<PolygonShape> _polygons;
@override@JsonKey() List<PolygonShape> get polygons {
  if (_polygons is EqualUnmodifiableListView) return _polygons;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_polygons);
}

 final  List<String> _draftVertexIds;
@override@JsonKey() List<String> get draftVertexIds {
  if (_draftVertexIds is EqualUnmodifiableListView) return _draftVertexIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_draftVertexIds);
}


/// Create a copy of Artwork
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ArtworkCopyWith<_Artwork> get copyWith => __$ArtworkCopyWithImpl<_Artwork>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Artwork&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&const DeepCollectionEquality().equals(other._vertices, _vertices)&&const DeepCollectionEquality().equals(other._polygons, _polygons)&&const DeepCollectionEquality().equals(other._draftVertexIds, _draftVertexIds));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,const DeepCollectionEquality().hash(_vertices),const DeepCollectionEquality().hash(_polygons),const DeepCollectionEquality().hash(_draftVertexIds));

@override
String toString() {
  return 'Artwork(id: $id, title: $title, vertices: $vertices, polygons: $polygons, draftVertexIds: $draftVertexIds)';
}


}

/// @nodoc
abstract mixin class _$ArtworkCopyWith<$Res> implements $ArtworkCopyWith<$Res> {
  factory _$ArtworkCopyWith(_Artwork value, $Res Function(_Artwork) _then) = __$ArtworkCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, Map<String, Vertex> vertices, List<PolygonShape> polygons, List<String> draftVertexIds
});




}
/// @nodoc
class __$ArtworkCopyWithImpl<$Res>
    implements _$ArtworkCopyWith<$Res> {
  __$ArtworkCopyWithImpl(this._self, this._then);

  final _Artwork _self;
  final $Res Function(_Artwork) _then;

/// Create a copy of Artwork
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? vertices = null,Object? polygons = null,Object? draftVertexIds = null,}) {
  return _then(_Artwork(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,vertices: null == vertices ? _self._vertices : vertices // ignore: cast_nullable_to_non_nullable
as Map<String, Vertex>,polygons: null == polygons ? _self._polygons : polygons // ignore: cast_nullable_to_non_nullable
as List<PolygonShape>,draftVertexIds: null == draftVertexIds ? _self._draftVertexIds : draftVertexIds // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}

// dart format on
