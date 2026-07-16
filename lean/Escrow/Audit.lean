import Escrow
open Escrow
-- Floor F1 headline
#print axioms reachable_safe
#print axioms certificate_implies_safety
-- Floor F2 headline + key lemmas
#print axioms durable_reachable_safe
#print axioms dreachable_Jinv
#print axioms Jinv_preserved
#print axioms durable_safety
-- Floor F2 negative controls
#print axioms Escrow.DurableNeg.lazy_debit_breaks_durable_bound
#print axioms Escrow.DurableNeg.volatile_dedup_breaks_durable_bound
