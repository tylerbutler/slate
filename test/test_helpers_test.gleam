import startest/expect
import test_helpers

pub fn range_inclusive_test() {
  test_helpers.range(1, 3) |> expect.to_equal([1, 2, 3])
}

pub fn range_empty_when_from_gt_to_test() {
  test_helpers.range(3, 1) |> expect.to_equal([])
}

pub fn cleanup_missing_file_test() {
  test_helpers.cleanup("test_helpers_missing_file.dets") |> expect.to_equal(Nil)
}
