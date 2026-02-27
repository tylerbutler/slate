import gleeunit/should
import test_helpers

pub fn range_inclusive_test() {
  test_helpers.range(1, 3) |> should.equal([1, 2, 3])
}

pub fn range_empty_when_from_gt_to_test() {
  test_helpers.range(3, 1) |> should.equal([])
}
