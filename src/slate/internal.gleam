/// Internal shared utilities for slate table modules.
///
/// This module is not part of the public API.
import gleam/dynamic/decode.{type Decoder, type Dynamic}
import gleam/list
import gleam/result
import slate

/// Decode a DETS tuple `{Key, Value}` using the given decoders.
pub fn tuple_decoder(
  key_decoder: Decoder(k),
  value_decoder: Decoder(v),
) -> Decoder(#(k, v)) {
  use k <- decode.field(0, key_decoder)
  use v <- decode.field(1, value_decoder)
  decode.success(#(k, v))
}

/// Decode a list of DETS tuple entries into typed key-value pairs.
pub fn decode_entries(
  entries: List(Dynamic),
  key_decoder: Decoder(k),
  value_decoder: Decoder(v),
) -> Result(List(#(k, v)), slate.DetsError) {
  let decoder = tuple_decoder(key_decoder, value_decoder)
  list.try_map(entries, fn(entry) {
    decode.run(entry, decoder)
    |> result.map_error(slate.DecodeErrors)
  })
}
