// Copyright (c) 2024 Elektrobit Automotive GmbH
//
// This program and the accompanying materials are made available under the
// terms of the Apache License, Version 2.0 which is available at
// https://www.apache.org/licenses/LICENSE-2.0.
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
// WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
// License for the specific language governing permissions and limitations
// under the License.
//
// SPDX-License-Identifier: Apache-2.0

use common::objects::{DeletedWorkload, FulfilledBy, WorkloadSpec};

#[cfg_attr(test, mockall_double::double)]
use crate::parameter_storage::ParameterStorage;

pub struct StateValidator {}

impl StateValidator {
    pub fn dependencies_for_workload_fulfilled(
        workload: &WorkloadSpec,
        workload_state_db: &ParameterStorage,
    ) -> bool {
        workload
            .dependencies
            .iter()
            .all(|(dependency_name, add_condition)| {
                workload_state_db
                    .get_state_of_workload(dependency_name)
                    .map_or(false, |wl_state| add_condition.fulfilled_by(&wl_state))
            })
    }

    pub fn dependencies_for_deleted_workload_fulfilled(
        workload: &DeletedWorkload,
        workload_state_db: &ParameterStorage,
    ) -> bool {
        workload
            .dependencies
            .iter()
            .all(|(dependency_name, delete_condition)| {
                workload_state_db
                    .get_state_of_workload(dependency_name)
                    .map_or(true, |wl_state| delete_condition.fulfilled_by(&wl_state))
            })
    }
}

//////////////////////////////////////////////////////////////////////////////
//                 ########  #######    #########  #########                //
//                    ##     ##        ##             ##                    //
//                    ##     #####     #########      ##                    //
//                    ##     ##                ##     ##                    //
//                    ##     #######   #########      ##                    //
//////////////////////////////////////////////////////////////////////////////

#[cfg(test)]
mod tests {
    use super::StateValidator;
    use common::objects::{
        generate_test_workload_spec_with_dependencies, AddCondition, ExecutionState,
    };
    use std::collections::HashMap;

    use crate::parameter_storage::MockParameterStorage;

    const AGENT_A: &str = "agent_A";
    const WORKLOAD_NAME_1: &str = "workload_1";
    const WORKLOAD_NAME_2: &str = "workload_2";
    const RUNTIME: &str = "runtime";

    #[test]
    fn utest_dependency_states_for_start_fulfilled() {
        let workload_with_dependencies = generate_test_workload_spec_with_dependencies(
            AGENT_A,
            WORKLOAD_NAME_1,
            RUNTIME,
            HashMap::from([(WORKLOAD_NAME_2.to_string(), AddCondition::AddCondRunning)]),
        );

        let mut parameter_storage_mock = MockParameterStorage::default();
        parameter_storage_mock
            .expect_get_state_of_workload()
            .once()
            .return_const(Some(ExecutionState::running()));

        assert!(StateValidator::dependencies_for_workload_fulfilled(
            &workload_with_dependencies,
            &parameter_storage_mock
        ));
    }

    #[test]
    fn utest_dependency_states_for_start_not_fulfilled() {
        let workload_with_dependencies = generate_test_workload_spec_with_dependencies(
            AGENT_A,
            WORKLOAD_NAME_1,
            RUNTIME,
            HashMap::from([(WORKLOAD_NAME_2.to_string(), AddCondition::AddCondRunning)]),
        );

        let mut parameter_storage_mock = MockParameterStorage::default();
        parameter_storage_mock
            .expect_get_state_of_workload()
            .once()
            .return_const(Some(ExecutionState::removed()));

        assert!(!StateValidator::dependencies_for_workload_fulfilled(
            &workload_with_dependencies,
            &parameter_storage_mock
        ));
    }

    #[test]
    fn utest_dependency_states_for_start_fulfilled_no_workload_state() {
        let workload_with_dependencies = generate_test_workload_spec_with_dependencies(
            AGENT_A,
            WORKLOAD_NAME_1,
            RUNTIME,
            HashMap::from([(WORKLOAD_NAME_2.to_string(), AddCondition::AddCondRunning)]),
        );

        let mut parameter_storage_mock = MockParameterStorage::default();
        parameter_storage_mock
            .expect_get_state_of_workload()
            .once()
            .return_const(None);

        assert!(!StateValidator::dependencies_for_workload_fulfilled(
            &workload_with_dependencies,
            &parameter_storage_mock
        ));
    }
}
