class_name TestCase
extends RefCounted
## Base dos testes unitários. Métodos que começam com "test_" são executados
## por tests/run_tests.gd. Use os assert_* abaixo.

var failures: PackedStringArray = []
var _atual := ""


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func assert_true(cond: bool, msg := "") -> void:
	if not cond:
		failures.append("%s: esperado verdadeiro. %s" % [_atual, msg])


func assert_false(cond: bool, msg := "") -> void:
	assert_true(not cond, msg)


func assert_eq(atual: Variant, esperado: Variant, msg := "") -> void:
	var igual: bool = (typeof(atual) == typeof(esperado) and atual == esperado) \
			or ((atual is float or atual is int) and (esperado is float or esperado is int) and is_equal_approx(float(atual), float(esperado)))
	if not igual:
		failures.append("%s: esperado <%s>, obtido <%s>. %s" % [_atual, esperado, atual, msg])


func assert_null(v: Variant, msg := "") -> void:
	if v != null:
		failures.append("%s: esperado null, obtido <%s>. %s" % [_atual, v, msg])


func assert_not_null(v: Variant, msg := "") -> void:
	if v == null:
		failures.append("%s: esperado não-null. %s" % [_atual, msg])


## Pasta temporária exclusiva do teste.
func tmp_dir() -> String:
	var d := "user://teste_tmp/%s" % _atual
	DirAccess.make_dir_recursive_absolute(d)
	return d
