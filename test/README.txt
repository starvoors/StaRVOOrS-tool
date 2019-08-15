This folder contains files which can be used to test StaRVOOrS. Below, you can find a description for them.

* Folder 'CoffeeBrew' contains the source code to be analised when running the tests.
* Folder 'ExpOut' contains files describing the output that is expected to be obtained when running StaRVOOrS against the files described above.
* Folder 'Specs' contains the ppDATE specfications used in the tests.
|-- File 'grammar.ppd' is meant to be run in only parsing mode. It is used to test the parser of the tool. It covers all of the features and constructs of the (ppDATE) script language. It should be parsed successfully.
|-- File 'pinit_section.ppd' is used to the test that templates are successfully instantiated at runtime when the PINIT section is used to create their instances.
|-- File 'automata_communication.ppd' is used to the test the communication between automata, using the action '\gen(e)' (i.e. e!) to generate the event e, and the trigger 'e?' to react to such an event.
|-- File 'monitor_behaviour.ppd' is used to test the behaviour of different monitor artifacts (at runtime), and the instansiation of templates using action \create.
|-- File 'templates_behaviour.ppd' to test the behaviour of templates when multiple instantiations of a template occur at runtime.
|-- File 'hoare_triples_behaviour.ppd' is used to test the verification of Hoare triples (at runtime).

-----------
-- TESTS --
-----------

Case 1 -> 8 receive
Case 2 -> 4 receive
Case 3 -> 2 instances of the template should be created
Case 4 -> Clean from main automaton 
          The value of tmp is : 10 
          Template created
          The value of tmp is : 20 
          Clean from main automaton 
          Clean from template 
          clean_filter_error_preOK
          clean_filter_error_bad
          !!!SYSTEM REACHED BAD STATE!!! in [clean_filter_error]
          The value of tmp is : 30
          The value of tmp is : 40
          !!!SYSTEM REACHED BAD STATE!!! in [prop1_tmp_cact1]
          !!!SYSTEM REACHED BAD STATE!!! in [prop]
Case 5 -> Three instances of the template

The value of tmp is : 10 
Template created 
The value of tmp is : 10 
Template created 
The value of tmp is : 20 
Clean from main automaton 
Clean from template 
clean_filter_error_preOK
clean_filter_error_bad
!!!SYSTEM REACHED BAD STATE!!! in [clean_filter_error]
The value of tmp is : 30
The value of tmp is : 40 
Clean from main automaton
The value of tmp is : 50
Clean from main automaton 
Clean from template 
The value of tmp is : 30 
The value of tmp is : 40 
!!!SYSTEM REACHED BAD STATE!!! in [prop1_tmp_cact1]
The value of tmp is : 10 
Template created 
The value of tmp is : 20 
!!!SYSTEM REACHED BAD STATE!!! in [prop]
!!!SYSTEM REACHED BAD STATE!!! in [prop1_tmp_cact1]

Case 6 -> 

