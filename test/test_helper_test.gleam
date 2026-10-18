import test_helper

pub fn range_inclusive_test() -> Nil {
  let assert True = test_helper.range(1, 3) == [1, 2, 3]
  Nil
}

pub fn range_single_element_test() -> Nil {
  let assert True = test_helper.range(5, 5) == [5]
  Nil
}

pub fn range_empty_when_from_greater_than_to_test() -> Nil {
  let assert True = test_helper.range(3, 1) == []
  Nil
}

pub fn cleanup_missing_file_test() -> Nil {
  let assert True = test_helper.cleanup("test_helpers_missing_file.dets") == Nil
  Nil
}
