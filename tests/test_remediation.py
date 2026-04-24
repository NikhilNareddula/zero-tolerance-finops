import os
import sys
import pytest
from unittest.mock import patch, MagicMock

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

# Mock boto3 before importing remediation module
with patch('boto3.client'):
    from src.remediation import evaluate_instance, get_monthly_cost


def test_get_monthly_cost_known_type():
    assert get_monthly_cost("t2.micro") == round(0.0116 * 730, 2)


def test_get_monthly_cost_unknown_type():
    assert get_monthly_cost("unknown.large") == 73.0


def test_evaluate_instance_prod_is_ignored():
    action, reason = evaluate_instance("i-123", {'env': 'prod', 'CostCenter': 'Ops'}, 'm5.large')
    assert action == 'IGNORE'
    assert 'Production' in reason


def test_evaluate_instance_exception_is_ignored():
    tags = {'Env': 'dev', 'CostCenter': 'Engineering', 'FinOpsException': 'Approved'}
    action, reason = evaluate_instance('i-456', tags, 'm5.large')
    assert action == 'IGNORE'
    assert 'Approved exception' in reason


def test_evaluate_instance_expensive_dev_is_stopped():
    tags = {'env': 'dev', 'CostCenter': 'Engineering'}
    action, reason = evaluate_instance('i-789', tags, 't2.medium', is_new_launch=True)
    assert action == 'STOP_IMMEDIATE'
    assert 'not allowed for dev environment' in reason


def test_evaluate_instance_missing_tags_warns_existing():
    tags = {'env': 'dev'}
    action, reason = evaluate_instance('i-101', tags, 't2.micro', is_new_launch=False)
    assert action == 'WARN'
    assert 'Missing tags' in reason


def test_evaluate_instance_missing_tags_stops_new_launch():
    tags = {'env': 'dev'}
    action, reason = evaluate_instance('i-202', tags, 't2.micro', is_new_launch=True)
    assert action == 'STOP_IMMEDIATE'
    assert 'Launched without required tags' in reason


def test_evaluate_instance_previous_warning_stops():
    tags = {'env': 'dev', 'FinOpsWarning': 'Action-Required'}
    action, reason = evaluate_instance('i-303', tags, 't2.micro', is_new_launch=False)
    assert action == 'STOP_PREVIOUS_WARN'
    assert 'Ignored warning' in reason
