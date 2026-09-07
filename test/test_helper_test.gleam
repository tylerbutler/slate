import startest/expect
import test_helper

pub fn range_inclusive_test() -> Nil {
  test_helper.range(1, 3) |> expect.to_equal([1, 2, 3])
}

pub fn range_single_element_test() -> Nil {
  test_helper.range(5, 5) |> expect.to_equal([5])
}

pub fn range_empty_when_from_greater_than_to_test() -> Nil {
  test_helper.range(3, 1) |> expect.to_equal([])
}

pub fn cleanup_missing_file_test() -> Nil {
  test_helper.cleanup("test_helpers_missing_file.dets") |> expect.to_equal(Nil)
}
