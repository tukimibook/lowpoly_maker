// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'artwork_summary.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ArtworkSummary {

 String get id; String get title; DateTime get updatedAt; String get thumbnailPath; String get documentPath;
/// Create a copy of ArtworkSummary
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ArtworkSummaryCopyWith<ArtworkSummary> get copyWith => _$ArtworkSummaryCopyWithImpl<ArtworkSummary>(this as ArtworkSummary, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ArtworkSummary&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.thumbnailPath, thumbnailPath) || other.thumbnailPath == thumbnailPath)&&(identical(other.documentPath, documentPath) || other.documentPath == documentPath));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,updatedAt,thumbnailPath,documentPath);

@override
String toString() {
  return 'ArtworkSummary(id: $id, title: $title, updatedAt: $updatedAt, thumbnailPath: $thumbnailPath, documentPath: $documentPath)';
}


}

/// @nodoc
abstract mixin class $ArtworkSummaryCopyWith<$Res>  {
  factory $ArtworkSummaryCopyWith(ArtworkSummary value, $Res Function(ArtworkSummary) _then) = _$ArtworkSummaryCopyWithImpl;
@useResult
$Res call({
 String id, String title, DateTime updatedAt, String thumbnailPath, String documentPath
});




}
/// @nodoc
class _$ArtworkSummaryCopyWithImpl<$Res>
    implements $ArtworkSummaryCopyWith<$Res> {
  _$ArtworkSummaryCopyWithImpl(this._self, this._then);

  final ArtworkSummary _self;
  final $Res Function(ArtworkSummary) _then;

/// Create a copy of ArtworkSummary
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? updatedAt = null,Object? thumbnailPath = null,Object? documentPath = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,thumbnailPath: null == thumbnailPath ? _self.thumbnailPath : thumbnailPath // ignore: cast_nullable_to_non_nullable
as String,documentPath: null == documentPath ? _self.documentPath : documentPath // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ArtworkSummary].
extension ArtworkSummaryPatterns on ArtworkSummary {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ArtworkSummary value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ArtworkSummary() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ArtworkSummary value)  $default,){
final _that = this;
switch (_that) {
case _ArtworkSummary():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ArtworkSummary value)?  $default,){
final _that = this;
switch (_that) {
case _ArtworkSummary() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  DateTime updatedAt,  String thumbnailPath,  String documentPath)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ArtworkSummary() when $default != null:
return $default(_that.id,_that.title,_that.updatedAt,_that.thumbnailPath,_that.documentPath);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  DateTime updatedAt,  String thumbnailPath,  String documentPath)  $default,) {final _that = this;
switch (_that) {
case _ArtworkSummary():
return $default(_that.id,_that.title,_that.updatedAt,_that.thumbnailPath,_that.documentPath);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  DateTime updatedAt,  String thumbnailPath,  String documentPath)?  $default,) {final _that = this;
switch (_that) {
case _ArtworkSummary() when $default != null:
return $default(_that.id,_that.title,_that.updatedAt,_that.thumbnailPath,_that.documentPath);case _:
  return null;

}
}

}

/// @nodoc


class _ArtworkSummary implements ArtworkSummary {
  const _ArtworkSummary({required this.id, required this.title, required this.updatedAt, required this.thumbnailPath, required this.documentPath});
  

@override final  String id;
@override final  String title;
@override final  DateTime updatedAt;
@override final  String thumbnailPath;
@override final  String documentPath;

/// Create a copy of ArtworkSummary
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ArtworkSummaryCopyWith<_ArtworkSummary> get copyWith => __$ArtworkSummaryCopyWithImpl<_ArtworkSummary>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ArtworkSummary&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.thumbnailPath, thumbnailPath) || other.thumbnailPath == thumbnailPath)&&(identical(other.documentPath, documentPath) || other.documentPath == documentPath));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,updatedAt,thumbnailPath,documentPath);

@override
String toString() {
  return 'ArtworkSummary(id: $id, title: $title, updatedAt: $updatedAt, thumbnailPath: $thumbnailPath, documentPath: $documentPath)';
}


}

/// @nodoc
abstract mixin class _$ArtworkSummaryCopyWith<$Res> implements $ArtworkSummaryCopyWith<$Res> {
  factory _$ArtworkSummaryCopyWith(_ArtworkSummary value, $Res Function(_ArtworkSummary) _then) = __$ArtworkSummaryCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, DateTime updatedAt, String thumbnailPath, String documentPath
});




}
/// @nodoc
class __$ArtworkSummaryCopyWithImpl<$Res>
    implements _$ArtworkSummaryCopyWith<$Res> {
  __$ArtworkSummaryCopyWithImpl(this._self, this._then);

  final _ArtworkSummary _self;
  final $Res Function(_ArtworkSummary) _then;

/// Create a copy of ArtworkSummary
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? updatedAt = null,Object? thumbnailPath = null,Object? documentPath = null,}) {
  return _then(_ArtworkSummary(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,thumbnailPath: null == thumbnailPath ? _self.thumbnailPath : thumbnailPath // ignore: cast_nullable_to_non_nullable
as String,documentPath: null == documentPath ? _self.documentPath : documentPath // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
