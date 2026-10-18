import test_helper

pub fn range_inclusive_test() -> Nil {
  assert test_helper.range(1, 3) == [1, 2, 3]
}

pub fn range_single_element_test() -> Nil {
  assert test_helper.range(5, 5) == [5]
}

pub fn range_empty_when_from_greater_than_to_test() -> Nil {
  assert test_helper.range(3, 1) == []
}

pub fn cleanup_missing_file_test() -> Nil {
  assert test_helper.cleanup("test_helpers_missing_file.dets") == Nil
}
