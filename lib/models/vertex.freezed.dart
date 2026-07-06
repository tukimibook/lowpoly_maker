// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'vertex.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Vertex {

 String get id; Offset get position;
/// Create a copy of Vertex
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VertexCopyWith<Vertex> get copyWith => _$VertexCopyWithImpl<Vertex>(this as Vertex, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Vertex&&(identical(other.id, id) || other.id == id)&&(identical(other.position, position) || other.position == position));
}


@override
int get hashCode => Object.hash(runtimeType,id,position);

@override
String toString() {
  return 'Vertex(id: $id, position: $position)';
}


}

/// @nodoc
abstract mixin class $VertexCopyWith<$Res>  {
  factory $VertexCopyWith(Vertex value, $Res Function(Vertex) _then) = _$VertexCopyWithImpl;
@useResult
$Res call({
 String id, Offset position
});




}
/// @nodoc
class _$VertexCopyWithImpl<$Res>
    implements $VertexCopyWith<$Res> {
  _$VertexCopyWithImpl(this._self, this._then);

  final Vertex _self;
  final $Res Function(Vertex) _then;

/// Create a copy of Vertex
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? position = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as Offset,
  ));
}

}


/// Adds pattern-matching-related methods to [Vertex].
extension VertexPatterns on Vertex {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Vertex value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Vertex() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Vertex value)  $default,){
final _that = this;
switch (_that) {
case _Vertex():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Vertex value)?  $default,){
final _that = this;
switch (_that) {
case _Vertex() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  Offset position)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Vertex() when $default != null:
return $default(_that.id,_that.position);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  Offset position)  $default,) {final _that = this;
switch (_that) {
case _Vertex():
return $default(_that.id,_that.position);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  Offset position)?  $default,) {final _that = this;
switch (_that) {
case _Vertex() when $default != null:
return $default(_that.id,_that.position);case _:
  return null;

}
}

}

/// @nodoc


class _Vertex implements Vertex {
  const _Vertex({required this.id, required this.position});
  

@override final  String id;
@override final  Offset position;

/// Create a copy of Vertex
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VertexCopyWith<_Vertex> get copyWith => __$VertexCopyWithImpl<_Vertex>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Vertex&&(identical(other.id, id) || other.id == id)&&(identical(other.position, position) || other.position == position));
}


@override
int get hashCode => Object.hash(runtimeType,id,position);

@override
String toString() {
  return 'Vertex(id: $id, position: $position)';
}


}

/// @nodoc
abstract mixin class _$VertexCopyWith<$Res> implements $VertexCopyWith<$Res> {
  factory _$VertexCopyWith(_Vertex value, $Res Function(_Vertex) _then) = __$VertexCopyWithImpl;
@override @useResult
$Res call({
 String id, Offset position
});




}
/// @nodoc
class __$VertexCopyWithImpl<$Res>
    implements _$VertexCopyWith<$Res> {
  __$VertexCopyWithImpl(this._self, this._then);

  final _Vertex _self;
  final $Res Function(_Vertex) _then;

/// Create a copy of Vertex
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? position = null,}) {
  return _then(_Vertex(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,position: null == position ? _self.position : position // ignore: cast_nullable_to_non_nullable
as Offset,
  ));
}


}

// dart format on
