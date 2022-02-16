"""
    default_update!(Uᵏ, Gᵏ, Fᵏ⁻¹, Gᵏ⁻¹) -> Uᵏ

Compute the correction of the current coarse value `Gᵏ` given the previous values `Fᵏ⁻¹` and `Gᵏ⁻¹`.
It is safe to work in-place.
There are two methods defined for this function:

```
default_update!(_, Gᵏ, Fᵏ⁻¹, Gᵏ⁻¹) = Gᵏ + Fᵏ⁻¹ + (-Gᵏ⁻¹) # out-of-place
default_update!(Uᵏ::Array, Gᵏ, Fᵏ⁻¹, Gᵏ⁻¹) = @. Uᵏ = Gᵏ + Fᵏ⁻¹ - Gᵏ⁻¹ # in-place
```

When extending the parareal method for custom types `T`,
you may either provide your own update function for [`Algorithm`](@ref),
or you may define `-(::T)` as well as `+(::T...)`.
Of course, a binary or tertiary `+` is also fine.
Defining a method for this function is not recommended.
"""
default_update!

default_update!(_, Gᵏ, Fᵏ⁻¹, Gᵏ⁻¹) = Gᵏ + Fᵏ⁻¹ + (-Gᵏ⁻¹) # out-of-place
default_update!(Uᵏ::Array, Gᵏ, Fᵏ⁻¹, Gᵏ⁻¹) = @. Uᵏ = Gᵏ + Fᵏ⁻¹ - Gᵏ⁻¹ # in-place
