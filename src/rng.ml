open Module_types
open Uncommon

module Numeric_of (Rng : Random.Rng) = struct

  type g = Rng.g

  module N_gen (N : Numeric.T) = struct

    type t = N.t
    type g = Rng.g

    let gen ?g n =
      if n < N.one then invalid_arg "rng: non-positive bound" ;

      let size   = N.bits (N.pred n) in
      let octets = cdiv size 8 in
      (* Generating octets * 4 makes ~94% cases covered in a single run. *)
      let batch  = Rng.(block_size * cdiv (octets * 4) block_size) in

      let rec attempt cs =
        try
          let x = N.of_bits_be cs size in
          if x < n then x else attempt (Cstruct.shift cs octets)
        with | Invalid_argument _ -> attempt Rng.(generate ?g batch) in
      attempt Rng.(generate ?g batch)

    let gen_r ?g a b = N.(a + gen ?g (b - a))

    let gen_bits ?g bits =

      let octets = cdiv bits 8 in
      let cs     = Rng.(generate ?g octets) in
      N.of_bits_be cs bits
  end

  module Int   = N_gen (Numeric.Int  )
  module Int32 = N_gen (Numeric.Int32)
  module Int64 = N_gen (Numeric.Int64)
  module ZN    = N_gen (Numeric.Z    )

  module Fc = struct
    type 'a t = (module Random.N with type g = g and type t = 'a)
    let int   : int   t = (module Int)
    let int32 : int32 t = (module Int32)
    let int64 : int64 t = (module Int64)
    let z     : Z.t   t = (module ZN)
  end

  let prime ?g ?(msb = 1) ~bits =
    if bits < 2 || bits < msb then invalid_arg "Rng.prime: bits too small";

    let limit = Z.(one lsl bits)
    and mask  = Z.((lsl) (pred (one lsl msb))) (bits - msb) in

    let rec attempt () =
      let p = Z.(nextprime @@ ZN.gen_bits ?g bits lor mask) in
      if p < limit then p else attempt () in
    attempt ()

  (* XXX Add ~msb param for p? *)
  let rec safe_prime ?g ~bits =
    let gg = prime ?g ~msb:1 ~bits:(bits - 1) in
    let p  = Z.(gg * z_two + one) in
    match Z.probab_prime p 25 with
    | 0 -> safe_prime ?g ~bits
    | _ -> (gg, p)

(*     |+ Pocklington primality test specialized for `a = 2`. +|
    if Z.(gcd (of_int 3) p = one) then (gg, p)
    else safe_prime ?g ~bits *)

  module Z = ZN

end


type g = Fortuna.g

open Fortuna

let gref = ref (create ())

let reseedv    = reseedv ~g:!gref
and reseed     = reseed  ~g:!gref
and seeded ()  = seeded  ~g:!gref
and set_gen ~g = gref := g

let block_size = block_size

let generate ?(g = !gref) n = generate ~g n

module Accumulator = struct
  (* XXX breaks down after set_gen. Make `g` and `acc` one-to-one? *)
  let acc    = Accumulator.create ~g:!gref
  let add    = Accumulator.add ~acc
  and add_rr = Accumulator.add_rr ~acc
end

include ( Numeric_of (
  struct
    type g = Fortuna.g
    let block_size = block_size
    let generate   = generate
  end
) : Random.Numeric with type g := g )
